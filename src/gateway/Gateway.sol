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
    function shouldRefuel(address source, bytes calldata payload) external view returns (bool);
}

interface RouterLike {
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
/// @notice Routing contract that forwards to multiple routers (1 full message, n-1 proofs)
///         and validates multiple routers have confirmed a message.
///
///         Supports processing multiple duplicate messages in parallel by
///         storing counts of messages and proofs that have been received.
contract Gateway is Auth, IGateway {
    using ArrayLib for uint16[8];
    using BytesLib for bytes;

    uint8 public constant MAX_ROUTER_COUNT = 8;
    uint8 public constant PRIMARY_ROUTER_ID = 1;
    uint256 public constant RECOVERY_CHALLENGE_PERIOD = 7 days;
    RootLike public immutable root;

    address public investmentManager;
    address public poolManager;
    GasServiceLike public gasService;

    address[] public routers;
    mapping(address router => Router) public activeRouters;
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
    function file(bytes32 what, address[] calldata routers_) external auth {
        if (what == "routers") {
            uint8 quorum_ = uint8(routers_.length);
            require(quorum_ > 0, "Gateway/empty-router-set");
            require(quorum_ <= MAX_ROUTER_COUNT, "Gateway/exceeds-max-router-count");

            uint64 sessionId = 0;
            if (routers.length > 0) {
                // Increment session id if it is not the initial router setup and the quorum was decreased
                Router memory prevRouter = activeRouters[routers[0]];
                sessionId = quorum_ < prevRouter.quorum ? prevRouter.activeSessionId + 1 : prevRouter.activeSessionId;
            }
            // Disable old routers
            for (uint8 i = 0; i < routers.length; i++) {
                delete activeRouters[routers[i]];
            }

            // Enable new routers, setting quorum to number of routers
            for (uint8 j; j < quorum_; j++) {
                require(activeRouters[routers_[j]].id == 0, "Gateway/no-duplicates-allowed");

                // Ids are assigned sequentially starting at 1
                activeRouters[routers_[j]] = Router(j + 1, quorum_, sessionId);
            }

            routers = routers_;
        } else {
            revert("Gateway/file-unrecognized-param");
        }

        emit File(what, routers_);
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

    // --- Incoming ---
    /// @inheritdoc IGateway
    function handle(bytes calldata message) external pauseable {
        Router memory router = activeRouters[msg.sender];
        require(router.id != 0, "Gateway/invalid-router");
        uint8 id = message.toUint8(0);
        address manager = messageHandlers[id];
        if (manager != address(0)) {
            ManagerLike(manager).handle(message);
        } else {
            _handle(message, msg.sender, router, false);
        }
    }

    function _handle(bytes calldata payload, address routerAddr, Router memory router, bool isRecovery) internal {
        MessagesLib.Call call = MessagesLib.messageType(payload);
        if (call == MessagesLib.Call.InitiateMessageRecovery || call == MessagesLib.Call.DisputeMessageRecovery) {
            require(!isRecovery, "Gateway/no-recursive-recovery-allowed");
            require(routers.length > 1, "Gateway/no-recovery-with-one-router-allowed");
            return _handleRecovery(payload);
        }

        bool isMessageProof = call == MessagesLib.Call.MessageProof;
        if (router.quorum == 1 && !isMessageProof) {
            // Special case for gas efficiency
            _dispatch(payload);
            emit ExecuteMessage(payload, routerAddr);
            return;
        }

        // Verify router and parse message hash
        bytes32 messageHash;
        if (isMessageProof) {
            require(isRecovery || router.id != PRIMARY_ROUTER_ID, "Gateway/non-proof-router");
            messageHash = payload.toBytes32(1);
            emit HandleProof(messageHash, routerAddr);
        } else {
            require(isRecovery || router.id == PRIMARY_ROUTER_ID, "Gateway/non-message-router");
            messageHash = keccak256(payload);
            emit HandleMessage(payload, routerAddr);
        }

        Message storage state = messages[messageHash];

        if (router.activeSessionId != state.sessionId) {
            // Clear votes from previous session
            delete state.votes;
            state.sessionId = router.activeSessionId;
        }

        // Increase vote
        state.votes[router.id - 1]++;

        if (state.votes.countNonZeroValues() >= router.quorum) {
            // Reduce votes by quorum
            state.votes.decreaseFirstNValues(router.quorum);

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

    function _handleRecovery(bytes memory payload) internal {
        if (MessagesLib.messageType(payload) == MessagesLib.Call.InitiateMessageRecovery) {
            bytes32 messageHash = payload.toBytes32(1);
            address router = payload.toAddress(33);
            require(activeRouters[msg.sender].id != 0, "Gateway/invalid-sender");
            require(activeRouters[router].id != 0, "Gateway/invalid-router");
            recoveries[messageHash] = Recovery(block.timestamp + RECOVERY_CHALLENGE_PERIOD, router);
            emit InitiateMessageRecovery(messageHash, router);
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
        Router storage router = activeRouters[recovery.router];

        require(recovery.timestamp != 0, "Gateway/message-recovery-not-initiated");
        require(recovery.timestamp <= block.timestamp, "Gateway/challenge-period-has-not-ended");
        require(router.id != 0, "Gateway/invalid-router");

        delete recoveries[messageHash];
        _handle(message, recovery.router, router, true);
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

        uint256 numRouters = routers.length;
        require(numRouters > 0, "Gateway/routers-not-initialized");
        uint256 fuel = quota;
        uint256 tank = fuel > 0 ? fuel : gasService.shouldRefuel(source, message) ? address(this).balance : 0;

        uint256 messageCost = gasService.estimate(message);
        uint256 proofCost = gasService.estimate(proof);

        for (uint256 i; i < numRouters; i++) {
            RouterLike currentRouter = RouterLike(routers[i]);
            bool isPrimaryRouter = i == PRIMARY_ROUTER_ID - 1;
            bytes memory payload = isPrimaryRouter ? message : proof;

            uint256 consumed = currentRouter.estimate(payload, isPrimaryRouter ? messageCost : proofCost);
            require(consumed <= tank, "Gateway/not-enough-gas-funds");
            tank -= consumed;

            currentRouter.pay{value: consumed}(payload, address(this));
            currentRouter.send(payload);
        }

        if (fuel > 0 && tank > 0) quota = 0;

        emit SendMessage(message);
    }

    function topUp() external payable {
        require(RootLike(root).endorsed(msg.sender), "Gateway/only-endorsed-can-topup");
        require(msg.value > 0, "Gateway/cannot-topup-with-nothing");
        quota = msg.value;
    }

    // --- Helpers ---
    /// @inheritdoc IGateway
    function quorum() external view returns (uint8) {
        Router memory router = activeRouters[routers[0]];
        return router.quorum;
    }

    /// @inheritdoc IGateway
    function activeSessionId() external view returns (uint64) {
        Router memory router = activeRouters[routers[0]];
        return router.activeSessionId;
    }

    /// @inheritdoc IGateway
    function votes(bytes32 messageHash) external view returns (uint16[8] memory) {
        return messages[messageHash].votes;
    }

    /// @inheritdoc IGateway
    function estimate(bytes calldata payload) external view returns (uint256[] memory tranches, uint256 total) {
        bytes memory proof = abi.encodePacked(uint8(MessagesLib.Call.MessageProof), keccak256(payload));
        uint256 proofCost = gasService.estimate(payload);
        uint256 messageCost = gasService.estimate(proof);
        tranches = new uint256[](routers.length);

        for (uint256 i; i < routers.length; i++) {
            uint256 centrifugeCost = i == PRIMARY_ROUTER_ID - 1 ? messageCost : proofCost;
            bytes memory message = i == PRIMARY_ROUTER_ID - 1 ? payload : proof;
            uint256 estimated = RouterLike(routers[i]).estimate(message, centrifugeCost);
            tranches[i] = estimated;
            total += estimated;
        }
    }

    function recoverTokens(address token, address receiver, uint256 amount) external auth {
        if (token == address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE)) {
            payable(receiver).transfer(amount);
        } else {
            SafeTransferLib.safeTransfer(token, receiver, amount);
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
            revert("Gateway/unsupported-message-id");
        }

        ManagerLike(manager).handle(message);
    }
}
