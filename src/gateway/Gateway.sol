// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.26;

import {Auth} from "src/Auth.sol";
import {ArrayLib} from "src/libraries/ArrayLib.sol";
import {BytesLib} from "src/libraries/BytesLib.sol";
import {MessagesLib} from "src/libraries/MessagesLib.sol";
import {SafeTransferLib} from "src/libraries/SafeTransferLib.sol";
import {TransientStorage} from "src/libraries/TransientStorage.sol";
import {IGateway, IMessageHandler} from "src/interfaces/gateway/IGateway.sol";
import {IRoot} from "src/interfaces/IRoot.sol";
import {IGasService} from "src/interfaces/gateway/IGasService.sol";
import {IAdapter} from "src/interfaces/gateway/IAdapter.sol";

/// @title  Gateway
/// @notice Routing contract that forwards to multiple adapters (1 full message, n-1 proofs)
///         and validates multiple adapters have confirmed a message.
///
///         Supports processing multiple duplicate messages in parallel by
///         storing counts of messages and proofs that have been received.
contract Gateway is Auth, IGateway {
    using ArrayLib for uint16[8];
    using BytesLib for bytes;
    using TransientStorage for bytes32;

    // The slot holding the quota state, transiently. bytes32(uint256(keccak256("quota")) - 1)
    bytes32 public constant QUOTA_SLOT = 0x1b6c99859b82987bd128ac509391b5af30e732c101d06c7836845a4a5b8e14f6;

    uint8 public constant MAX_ADAPTER_COUNT = 8;
    uint8 public constant PRIMARY_ADAPTER_ID = 1;
    uint256 public constant RECOVERY_CHALLENGE_PERIOD = 7 days;

    IRoot public immutable root;

    address public poolManager;
    address public investmentManager;
    IGasService public gasService;

    address[] public adapters;
    mapping(address adapter => Adapter) public activeAdapters;
    mapping(bytes32 messageHash => Message) public messages;
    mapping(uint8 messageId => address manager) messageHandlers;
    mapping(address router => mapping(bytes32 messageHash => uint256 timestamp)) public recoveries;

    constructor(address root_, address poolManager_, address investmentManager_, address gasService_) {
        root = IRoot(root_);
        poolManager = poolManager_;
        investmentManager = investmentManager_;
        gasService = IGasService(gasService_);

        wards[msg.sender] = 1;
        emit Rely(msg.sender);
    }

    modifier pauseable() {
        require(!root.paused(), "Gateway/paused");
        _;
    }

    receive() external payable {
        emit Received(msg.sender, msg.value);
    }

    // --- Administration ---
    /// @inheritdoc IGateway
    function file(bytes32 what, address[] calldata adapters_) external auth {
        if (what == "adapters") {
            uint8 quorum_ = uint8(adapters_.length);
            require(quorum_ > 0, "Gateway/empty-adapter-set");
            require(quorum_ <= MAX_ADAPTER_COUNT, "Gateway/exceeds-max-adapter-count");

            uint64 sessionId = 0;
            if (adapters.length > 0) {
                // Increment session id if it is not the initial adapter setup and the quorum was decreased
                Adapter memory prevAdapter = activeAdapters[adapters[0]];
                sessionId = quorum_ < prevAdapter.quorum ? prevAdapter.activeSessionId + 1 : prevAdapter.activeSessionId;
            }
            // Disable old adapters
            for (uint8 i = 0; i < adapters.length; i++) {
                delete activeAdapters[adapters[i]];
            }

            // Enable new adapters, setting quorum to number of adapters
            for (uint8 j; j < quorum_; j++) {
                require(activeAdapters[adapters_[j]].id == 0, "Gateway/no-duplicates-allowed");

                // Ids are assigned sequentially starting at 1
                activeAdapters[adapters_[j]] = Adapter(j + 1, quorum_, sessionId);
            }

            adapters = adapters_;
        } else {
            revert("Gateway/file-unrecognized-param");
        }

        emit File(what, adapters_);
    }

    /// @inheritdoc IGateway
    function file(bytes32 what, address instance) external auth {
        if (what == "gasService") gasService = IGasService(instance);
        else if (what == "investmentManager") investmentManager = instance;
        else if (what == "poolManager") poolManager = instance;
        else revert("Gateway/file-unrecognized-param");

        emit File(what, instance);
    }

    /// @inheritdoc IGateway
    function file(bytes32 what, uint8 data1, address data2) public auth {
        if (what == "message") messageHandlers[data1] = data2;
        else revert("Gateway/file-unrecognized-param");
        emit File(what, data1, data2);
    }

    function recoverTokens(address token, address receiver, uint256 amount) external auth {
        if (token == address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE)) {
            payable(receiver).transfer(amount);
        } else {
            SafeTransferLib.safeTransfer(token, receiver, amount);
        }
    }

    // --- Incoming ---
    /// @inheritdoc IGateway
    function handle(bytes calldata message) external pauseable {
        _handle(message, msg.sender, false);
    }

    function _handle(bytes calldata payload, address adapter_, bool isRecovery) internal {
        Adapter memory adapter = activeAdapters[adapter_];
        require(adapter.id != 0, "Gateway/invalid-adapter");
        uint8 call = payload.toUint8(0);
        if (
            call == uint8(MessagesLib.Call.InitiateMessageRecovery)
                || call == uint8(MessagesLib.Call.DisputeMessageRecovery)
        ) {
            require(!isRecovery, "Gateway/no-recursive-recovery-allowed");
            require(adapters.length > 1, "Gateway/no-recovery-with-one-adapter-allowed");
            return _handleRecovery(payload);
        }

        bool isMessageProof = call == uint8(MessagesLib.Call.MessageProof);
        if (adapter.quorum == 1 && !isMessageProof) {
            // Special case for gas efficiency
            _dispatch(payload);
            emit ExecuteMessage(payload, adapter_);
            return;
        }

        // Verify adapter and parse message hash
        bytes32 messageHash;
        if (isMessageProof) {
            require(isRecovery || adapter.id != PRIMARY_ADAPTER_ID, "Gateway/non-proof-adapter");
            messageHash = payload.toBytes32(1);
            emit HandleProof(messageHash, adapter_);
        } else {
            require(isRecovery || adapter.id == PRIMARY_ADAPTER_ID, "Gateway/non-message-adapter");
            messageHash = keccak256(payload);
            emit HandleMessage(payload, adapter_);
        }

        Message storage state = messages[messageHash];

        if (adapter.activeSessionId != state.sessionId) {
            // Clear votes from previous session
            delete state.votes;
            state.sessionId = adapter.activeSessionId;
        }

        // Increase vote
        state.votes[adapter.id - 1]++;

        if (state.votes.countNonZeroValues() >= adapter.quorum) {
            // Reduce votes by quorum
            state.votes.decreaseFirstNValues(adapter.quorum);

            // Handle message
            if (isMessageProof) {
                _dispatch(state.pendingMessage);
            } else {
                _dispatch(payload);
            }

            // Only if there are no more pending messages, remove the pending message
            if (state.votes.isEmpty()) {
                delete state.pendingMessage;
            }

            emit ExecuteMessage(payload, msg.sender);
        } else if (!isMessageProof) {
            state.pendingMessage = payload;
        }
    }

    function _dispatch(bytes memory message) internal {
        uint8 id = message.toUint8(0);
        address manager;

        // Hardcoded paths for root + pool & investment managers for gas efficiency
        if (id >= 1 && id <= 8 || id >= 23 && id <= 26 || id == 32) {
            manager = poolManager;
        } else if (id >= 9 && id <= 20 || id == 27) {
            manager = investmentManager;
        } else if (id >= 21 && id <= 22 || id == 31) {
            manager = address(root);
        } else {
            // Dynamic path for other managers, to be able to easily
            // extend functionality of Liquidity Pools
            manager = messageHandlers[id];
            require(manager != address(0), "Gateway/unregistered-message-id");
        }

        IMessageHandler(manager).handle(message);
    }

    function _handleRecovery(bytes memory payload) internal {
        bytes32 messageHash = payload.toBytes32(1);
        address adapter = payload.toAddress(33);

        if (MessagesLib.messageType(payload) == MessagesLib.Call.InitiateMessageRecovery) {
            require(activeAdapters[msg.sender].id != 0, "Gateway/invalid-sender");
            require(activeAdapters[adapter].id != 0, "Gateway/invalid-adapter");
            recoveries[adapter][messageHash] = block.timestamp + RECOVERY_CHALLENGE_PERIOD;
            emit InitiateMessageRecovery(messageHash, adapter);
        } else if (MessagesLib.messageType(payload) == MessagesLib.Call.DisputeMessageRecovery) {
            return _disputeMessageRecovery(adapter, messageHash);
        }
    }

    function disputeMessageRecovery(address adapter, bytes32 messageHash) external auth {
        _disputeMessageRecovery(adapter, messageHash);
    }

    function _disputeMessageRecovery(address adapter, bytes32 messageHash) internal {
        delete recoveries[adapter][messageHash];
        emit DisputeMessageRecovery(messageHash, adapter);
    }

    /// @inheritdoc IGateway
    function executeMessageRecovery(address adapter, bytes calldata message) external {
        bytes32 messageHash = keccak256(message);
        uint256 recovery = recoveries[adapter][messageHash];

        require(recovery != 0, "Gateway/message-recovery-not-initiated");
        require(recovery <= block.timestamp, "Gateway/challenge-period-has-not-ended");

        delete recoveries[adapter][messageHash];
        _handle(message, adapter, true);
        emit ExecuteMessageRecovery(message, adapter);
    }

    // --- Outgoing ---
    /// @inheritdoc IGateway
    function send(bytes calldata message, address source) public payable pauseable {
        require(
            msg.sender == investmentManager || msg.sender == poolManager
                || msg.sender == messageHandlers[message.toUint8(0)],
            "Gateway/invalid-manager"
        );

        bytes memory proof = abi.encodePacked(uint8(MessagesLib.Call.MessageProof), keccak256(message));

        uint256 numAdapters = adapters.length;
        require(numAdapters > 0, "Gateway/adapters-not-initialized");

        uint256 fuel = QUOTA_SLOT.tloadUint256();
        uint256 messageCost = gasService.estimate(message);
        uint256 proofCost = gasService.estimate(proof);

        if (fuel > 0) {
            uint256 tank = fuel;
            for (uint256 i; i < numAdapters; i++) {
                IAdapter currentAdapter = IAdapter(adapters[i]);
                bool isPrimaryAdapter = i == PRIMARY_ADAPTER_ID - 1;
                bytes memory payload = isPrimaryAdapter ? message : proof;

                uint256 consumed = currentAdapter.estimate(payload, isPrimaryAdapter ? messageCost : proofCost);

                require(consumed <= tank, "Gateway/not-enough-gas-funds");
                tank -= consumed;

                currentAdapter.pay{value: consumed}(payload, address(this));

                currentAdapter.send(payload);
            }
            QUOTA_SLOT.tstore(0);
        } else if (gasService.shouldRefuel(source, message)) {
            uint256 tank = address(this).balance;
            for (uint256 i; i < numAdapters; i++) {
                IAdapter currentAdapter = IAdapter(adapters[i]);
                bool isPrimaryAdapter = i == PRIMARY_ADAPTER_ID - 1;
                bytes memory payload = isPrimaryAdapter ? message : proof;

                uint256 consumed = currentAdapter.estimate(payload, isPrimaryAdapter ? messageCost : proofCost);

                if (consumed <= tank) {
                    tank -= consumed;
                    currentAdapter.pay{value: consumed}(payload, address(this));
                }

                currentAdapter.send(payload);
            }
        } else {
            revert("Gateway/not-enough-gas-funds");
        }

        emit SendMessage(message);
    }

    /// @inheritdoc IGateway
    function topUp() external payable {
        require(IRoot(root).endorsed(msg.sender), "Gateway/only-endorsed-can-topup");
        require(msg.value > 0, "Gateway/cannot-topup-with-nothing");
        QUOTA_SLOT.tstore(msg.value);
    }

    // --- Helpers ---
    /// @inheritdoc IGateway
    function estimate(bytes calldata payload) external view returns (uint256[] memory tranches, uint256 total) {
        bytes memory proof = abi.encodePacked(uint8(MessagesLib.Call.MessageProof), keccak256(payload));
        uint256 proofCost = gasService.estimate(payload);
        uint256 messageCost = gasService.estimate(proof);
        tranches = new uint256[](adapters.length);

        for (uint256 i; i < adapters.length; i++) {
            uint256 centrifugeCost = i == PRIMARY_ADAPTER_ID - 1 ? messageCost : proofCost;
            bytes memory message = i == PRIMARY_ADAPTER_ID - 1 ? payload : proof;
            uint256 estimated = IAdapter(adapters[i]).estimate(message, centrifugeCost);
            tranches[i] = estimated;
            total += estimated;
        }
    }

    /// @inheritdoc IGateway
    function quorum() external view returns (uint8) {
        Adapter memory adapter = activeAdapters[adapters[0]];
        return adapter.quorum;
    }

    /// @inheritdoc IGateway
    function activeSessionId() external view returns (uint64) {
        Adapter memory adapter = activeAdapters[adapters[0]];
        return adapter.activeSessionId;
    }

    /// @inheritdoc IGateway
    function votes(bytes32 messageHash) external view returns (uint16[8] memory) {
        return messages[messageHash].votes;
    }
}
