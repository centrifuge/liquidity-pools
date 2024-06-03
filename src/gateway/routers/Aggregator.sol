// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import {Auth} from "src/Auth.sol";
import {ArrayLib} from "src/libraries/ArrayLib.sol";
import {BytesLib} from "src/libraries/BytesLib.sol";
import {MessagesLib} from "src/libraries/MessagesLib.sol";
import {IAggregator} from "src/interfaces/gateway/IAggregator.sol";

interface GatewayLike {
    function handle(bytes memory message) external;
}

interface RouterLike {
    function send(bytes memory message) external;
}

/// @title  Aggregator
/// @notice Routing contract that forwards to multiple routers (1 full message, n-1 proofs)
///         and validates multiple routers have confirmed a message.
///
///         Supports processing multiple duplicate messages in parallel by
///         storing counts of messages and proofs that have been received.
contract Aggregator is Auth, IAggregator {
    using ArrayLib for uint16[MAX_ROUTER_COUNT];
    using BytesLib for bytes;

    uint8 public constant MAX_ROUTER_COUNT = 8;
    uint8 public constant PRIMARY_ROUTER_ID = 1;
    uint256 public constant RECOVERY_CHALLENGE_PERIOD = 7 days;

    GatewayLike public immutable gateway;

    address[] public routers;
    mapping(address router => Router) public activeRouters;
    mapping(bytes32 messageHash => Message) public messages;
    mapping(bytes32 messageHash => Recovery) public recoveries;

    constructor(address gateway_) {
        gateway = GatewayLike(gateway_);

        wards[msg.sender] = 1;
        emit Rely(msg.sender);
    }

    // --- Administration ---
    /// @inheritdoc IAggregator
    function file(bytes32 what, address[] calldata routers_) external auth {
        if (what == "routers") {
            uint8 quorum_ = uint8(routers_.length);
            require(quorum_ > 0, "Aggregator/empty-router-set");
            require(quorum_ <= MAX_ROUTER_COUNT, "Aggregator/exceeds-max-router-count");

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
                require(activeRouters[routers_[j]].id == 0, "Aggregator/no-duplicates-allowed");

                // Ids are assigned sequentially starting at 1
                activeRouters[routers_[j]] = Router(j + 1, quorum_, sessionId);
            }

            routers = routers_;
        } else {
            revert("Aggregator/file-unrecognized-param");
        }

        emit File(what, routers_);
    }

    // --- Incoming ---
    /// @inheritdoc IAggregator
    function handle(bytes calldata payload) external {
        Router memory router = activeRouters[msg.sender];
        require(router.id != 0, "Aggregator/invalid-router");
        _handle(payload, msg.sender, router, false);
    }

    function _handle(bytes calldata payload, address routerAddr, Router memory router, bool isRecovery) internal {
        MessagesLib.Call call = MessagesLib.messageType(payload);
        if (call == MessagesLib.Call.InitiateMessageRecovery || call == MessagesLib.Call.DisputeMessageRecovery) {
            require(!isRecovery, "Aggregator/no-recursive-recovery-allowed");
            require(routers.length > 1, "Aggregator/no-recovery-with-one-router-allowed");
            return _handleRecovery(payload);
        }

        bool isMessageProof = call == MessagesLib.Call.MessageProof;
        if (router.quorum == 1 && !isMessageProof) {
            // Special case for gas efficiency
            gateway.handle(payload);
            emit ExecuteMessage(payload, routerAddr);
            return;
        }

        // Verify router and parse message hash
        bytes32 messageHash;
        if (isMessageProof) {
            require(isRecovery || router.id != PRIMARY_ROUTER_ID, "RouterAggregator/non-proof-router");
            messageHash = payload.toBytes32(1);
            emit HandleProof(messageHash, routerAddr);
        } else {
            require(isRecovery || router.id == PRIMARY_ROUTER_ID, "RouterAggregator/non-message-router");
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
                gateway.handle(state.pendingMessage);
            } else {
                gateway.handle(payload);
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
            require(activeRouters[msg.sender].id != 0, "Aggregator/invalid-sender");
            require(activeRouters[router].id != 0, "Aggregator/invalid-router");
            recoveries[messageHash] = Recovery(block.timestamp + RECOVERY_CHALLENGE_PERIOD, router);
            emit InitiateMessageRecovery(messageHash, router);
        } else if (MessagesLib.messageType(payload) == MessagesLib.Call.DisputeMessageRecovery) {
            bytes32 messageHash = payload.toBytes32(1);
            return _disputeMessageRecovery(messageHash);
        }
    }

    /// @inheritdoc IAggregator
    function disputeMessageRecovery(bytes32 messageHash) external auth {
        _disputeMessageRecovery(messageHash);
    }

    function _disputeMessageRecovery(bytes32 messageHash) internal {
        delete recoveries[messageHash];
        emit DisputeMessageRecovery(messageHash);
    }

    /// @inheritdoc IAggregator
    function executeMessageRecovery(bytes calldata message) external {
        bytes32 messageHash = keccak256(message);
        Recovery storage recovery = recoveries[messageHash];
        Router storage router = activeRouters[recovery.router];

        require(recovery.timestamp != 0, "Aggregator/message-recovery-not-initiated");
        require(recovery.timestamp <= block.timestamp, "Aggregator/challenge-period-has-not-ended");
        require(router.id != 0, "Aggregator/invalid-router");

        delete recoveries[messageHash];
        _handle(message, recovery.router, router, true);
        emit ExecuteMessageRecovery(message);
    }

    // --- Outgoing ---
    /// @inheritdoc IAggregator
    function send(bytes calldata message) external auth {
        uint256 numRouters = routers.length;
        require(numRouters > 0, "Aggregator/not-initialized");

        bytes memory proof = abi.encodePacked(uint8(MessagesLib.Call.MessageProof), keccak256(message));
        for (uint256 i; i < numRouters; i++) {
            RouterLike(routers[i]).send(i == PRIMARY_ROUTER_ID - 1 ? message : proof);
        }

        emit SendMessage(message);
    }

    // --- Helpers ---
    /// @inheritdoc IAggregator
    function quorum() external view returns (uint8) {
        Router memory router = activeRouters[routers[0]];
        return router.quorum;
    }

    /// @inheritdoc IAggregator
    function activeSessionId() external view returns (uint64) {
        Router memory router = activeRouters[routers[0]];
        return router.activeSessionId;
    }

    /// @inheritdoc IAggregator
    function votes(bytes32 messageHash) external view returns (uint16[8] memory) {
        return messages[messageHash].votes;
    }
}
