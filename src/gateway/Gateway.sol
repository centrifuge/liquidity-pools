// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import {Auth} from "src/Auth.sol";
import {ArrayLib} from "src/libraries/ArrayLib.sol";
import {BytesLib} from "src/libraries/BytesLib.sol";
import {MessagesLib} from "src/libraries/MessagesLib.sol";
import {SafeTransferLib} from "src/libraries/SafeTransferLib.sol";
import {IGateway} from "src/interfaces/gateway/IGateway.sol";

interface ManagerLike {
    function handle(bytes memory message) external;
}

interface GasServiceLike {
    function estimate(bytes calldata payload) external view returns (uint256);
    function shouldRefuel(address source, bytes calldata payload) external returns (bool);
}

interface AdapterLike {
    function send(bytes memory message) external;
    function pay(bytes calldata payload, address refund) external payable;
    function estimate(bytes calldata payload, uint256 destChainCost) external view returns (uint256);
}

interface RootLike {
    function paused() external returns (bool);
    function scheduleRely(address target) external;
    function cancelRely(address target) external;
    function recoverTokens(address target, address token, address to, uint256 amount) external;
    function endorsed(address user) external view returns (bool);
}

/// @title  Gateway
/// @notice Routing contract that forwards to multiple adapters (1 full message, n-1 proofs)
///         and validates multiple adapters have confirmed a message.
///
///         Supports processing multiple duplicate messages in parallel by
///         storing counts of messages and proofs that have been received.
contract Gateway is Auth, IGateway {
    using ArrayLib for uint16[8];
    using BytesLib for bytes;

    uint8 public constant MAX_ADAPTER_COUNT = 8;
    uint8 public constant PRIMARY_ADAPTER_ID = 1;
    uint256 public constant RECOVERY_CHALLENGE_PERIOD = 7 days;
    RootLike public immutable root;

    address public investmentManager;
    address public poolManager;
    GasServiceLike public gasService;

    address[] public adapters;
    mapping(address adapter => Adapter) public activeAdapters;
    mapping(bytes32 messageHash => Message) public messages;
    mapping(bytes32 messageHash => Recovery) public recoveries;
    mapping(uint8 messageId => address manager) messageHandlers;

    uint256 quota;

    constructor(address root_, address investmentManager_, address poolManager_, address gasService_) {
        root = RootLike(root_);
        investmentManager = investmentManager_;
        poolManager = poolManager_;
        gasService = GasServiceLike(gasService_);

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
        if (what == "gasService") gasService = GasServiceLike(instance);
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
        Adapter memory adapter = activeAdapters[msg.sender];
        require(adapter.id != 0, "Gateway/invalid-adapter");
        _handle(message, msg.sender, adapter, false);
    }

    function _handle(bytes calldata payload, address adapterAddr, Adapter memory adapter, bool isRecovery) internal {
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
            emit ExecuteMessage(payload, adapterAddr);
            return;
        }

        // Verify adapter and parse message hash
        bytes32 messageHash;
        if (isMessageProof) {
            require(isRecovery || adapter.id != PRIMARY_ADAPTER_ID, "Gateway/non-proof-adapter");
            messageHash = payload.toBytes32(1);
            emit HandleProof(messageHash, adapterAddr);
        } else {
            require(isRecovery || adapter.id == PRIMARY_ADAPTER_ID, "Gateway/non-message-adapter");
            messageHash = keccak256(payload);
            emit HandleMessage(payload, adapterAddr);
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

        ManagerLike(manager).handle(message);
    }

    function _handleRecovery(bytes memory payload) internal {
        if (MessagesLib.messageType(payload) == MessagesLib.Call.InitiateMessageRecovery) {
            bytes32 messageHash = payload.toBytes32(1);
            address adapter = payload.toAddress(33);
            require(activeAdapters[msg.sender].id != 0, "Gateway/invalid-sender");
            require(activeAdapters[adapter].id != 0, "Gateway/invalid-adapter");
            recoveries[messageHash] = Recovery(block.timestamp + RECOVERY_CHALLENGE_PERIOD, adapter);
            emit InitiateMessageRecovery(messageHash, adapter);
        } else if (MessagesLib.messageType(payload) == MessagesLib.Call.DisputeMessageRecovery) {
            bytes32 messageHash = payload.toBytes32(1);
            return _disputeMessageRecovery(messageHash);
        }
    }

    /// @inheritdoc IGateway
    function disputeMessageRecovery(bytes32 messageHash) external auth {
        _disputeMessageRecovery(messageHash);
    }

    function _disputeMessageRecovery(bytes32 messageHash) internal {
        delete recoveries[messageHash];
        emit DisputeMessageRecovery(messageHash);
    }

    /// @inheritdoc IGateway
    function executeMessageRecovery(bytes calldata message) external {
        bytes32 messageHash = keccak256(message);
        // wouldn't it better to mark these as memory?
        Recovery storage recovery = recoveries[messageHash];
        Adapter storage adapter = activeAdapters[recovery.adapter];

        require(recovery.timestamp != 0, "Gateway/message-recovery-not-initiated");
        require(recovery.timestamp <= block.timestamp, "Gateway/challenge-period-has-not-ended");
        require(adapter.id != 0, "Gateway/invalid-adapter");

        delete recoveries[messageHash];
        _handle(message, recovery.adapter, adapter, true);
        emit ExecuteMessageRecovery(message);
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

        uint256 fuel = quota;
        uint256 messageCost = gasService.estimate(message);
        uint256 proofCost = gasService.estimate(proof);

        if (fuel > 0) {
            uint256 tank = fuel;
            for (uint256 i; i < numAdapters; i++) {
                AdapterLike currentAdapter = AdapterLike(adapters[i]);
                bool isPrimaryAdapter = i == PRIMARY_ADAPTER_ID - 1;
                bytes memory payload = isPrimaryAdapter ? message : proof;

                uint256 consumed = currentAdapter.estimate(payload, isPrimaryAdapter ? messageCost : proofCost);

                require(consumed <= tank, "Gateway/not-enough-gas-funds");
                tank -= consumed;

                currentAdapter.pay{value: consumed}(payload, address(this));

                currentAdapter.send(payload);
            }
            quota = 0;
        } else if (gasService.shouldRefuel(source, message)) {
            uint256 tank = address(this).balance;
            for (uint256 i; i < numAdapters; i++) {
                AdapterLike currentAdapter = AdapterLike(adapters[i]);
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
        require(RootLike(root).endorsed(msg.sender), "Gateway/only-endorsed-can-topup");
        require(msg.value > 0, "Gateway/cannot-topup-with-nothing");
        quota = msg.value;
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
            uint256 estimated = AdapterLike(adapters[i]).estimate(message, centrifugeCost);
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
