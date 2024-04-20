// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import {Auth} from "src/Auth.sol";
import {ArrayLib} from "src/libraries/ArrayLib.sol";
import {MessagesLib} from "src/libraries/MessagesLib.sol";

interface GatewayLike {
    function handle(bytes memory message) external;
}

interface RouterLike {
    function send(bytes memory message) external;
    function pay(address sender, bytes calldata payload) external payable;
    function estimate(uint256 baseCost) external returns (uint256);
}

/// @title  RouterAggregator
/// @notice Routing contract that forwards to multiple routers (1 full message, n-1 proofs)
///         and validates multiple routers have confirmed a message.
///
///         Supports processing multiple duplicate messages in parallel by
///         storing counts of messages and proofs that have been received.
contract RouterAggregator is Auth {
    using ArrayLib for uint16[8];

    uint8 public constant MAX_ROUTER_COUNT = 8;
    uint8 public constant PRIMARY_ROUTER_ID = 1;
    uint256 public constant RECOVERY_CHALLENGE_PERIOD = 7 days;

    GatewayLike public immutable gateway;

    address[] public routers;
    mapping(address router => Router) public validRouters;
    mapping(bytes32 messageHash => Recovery) public recoveries;
    mapping(bytes32 messageHash => bytes) public pendingMessages;
    mapping(bytes32 messageHash => ConfirmationState) internal _confirmations;

    struct Router {
        // Starts at 1 and maps to id - 1 as the index on the routers array
        uint8 id;
        // Each router struct is packed with the quorum to reduce SLOADs on handle
        uint8 quorum;
    }

    struct ConfirmationState {
        // Counts are stored as integers (instead of boolean values) to accommodate duplicate
        // messages (e.g. two investments from the same user with the same amount) being
        // processed in parallel. The entire struct is packed in a single bytes32 slot.
        // Max uint16 = 65,535 so at most 65,535 duplicate messages can be processed in parallel.
        uint16[8] messages;
        uint16[8] proofs;
    }

    struct Recovery {
        uint256 timestamp;
        address router;
    }

    // --- Events ---
    event HandleMessage(bytes message, address router);
    event HandleProof(bytes32 messageHash, address router);
    event ExecuteMessage(bytes message, address router);
    event SendMessage(bytes message);
    event RecoverMessage(address router, bytes message);
    event RecoverProof(address router, bytes32 messageHash);
    event InitiateMessageRecovery(bytes32 messageHash, address router);
    event DisputeMessageRecovery(bytes32 messageHash);
    event ExecuteMessagRecovery(bytes message);
    event File(bytes32 indexed what, address[] routers);

    constructor(address gateway_) {
        gateway = GatewayLike(gateway_);

        wards[msg.sender] = 1;
        emit Rely(msg.sender);
    }

    // --- Administration ---
    function file(bytes32 what, address[] calldata routers_) external auth {
        if (what == "routers") {
            require(routers_.length <= MAX_ROUTER_COUNT, "RouterAggregator/exceeds-max-router-count");

            // Disable old routers
            for (uint8 i = 0; i < routers.length; ++i) {
                delete validRouters[address(routers[i])];
            }

            // Enable new routers, setting quorum to number of routers
            uint8 quorum_ = uint8(routers_.length);
            for (uint8 j; j < quorum_; ++j) {
                // Ids are assigned sequentially starting at 1
                validRouters[routers_[j]] = Router(j + 1, quorum_);
            }

            routers = routers_;
        } else {
            revert("RouterAggregator/file-unrecognized-param");
        }

        emit File(what, routers_);
    }

    // --- Incoming ---
    /// @dev Handle incoming messages, proofs, and recoveries.
    ///      Assumes routers ensure messages cannot be confirmed more than once.
    function handle(bytes calldata payload) public {
        Router memory router = validRouters[msg.sender];
        require(router.id != 0, "RouterAggregator/invalid-router");
        _handle(payload, router);
    }

    function _handle(bytes calldata payload, Router memory router) internal {
        if (MessagesLib.isRecoveryMessage(payload)) {
            require(routers.length > 1, "RouterAggregator/no-recovery-with-one-router-allowed");
            return _handleRecovery(payload);
        }

        bool isMessageProof = MessagesLib.messageType(payload) == MessagesLib.Call.MessageProof;
        if (router.quorum == 1 && !isMessageProof) {
            // Special case for gas efficiency
            gateway.handle(payload);
            emit ExecuteMessage(payload, msg.sender);
            return;
        }

        bytes32 messageHash;
        ConfirmationState storage state;
        if (isMessageProof) {
            messageHash = MessagesLib.parseMessageProof(payload);
            state = _confirmations[messageHash];
            state.proofs[router.id - 1]++;

            emit HandleProof(messageHash, msg.sender);
        } else {
            messageHash = keccak256(payload);
            state = _confirmations[messageHash];
            state.messages[router.id - 1]++;

            emit HandleMessage(payload, msg.sender);
        }

        if (state.messages.countNonZeroValues() >= 1 && state.proofs.countNonZeroValues() >= router.quorum - 1) {
            // Reduce total message confirmation count by 1, by finding the first non-zero value
            state.messages.decreaseFirstNValues(1, 1);

            // Reduce total proof confiration count by quorum
            state.proofs.decreaseFirstNValues(router.quorum, 1);

            if (isMessageProof) {
                gateway.handle(pendingMessages[messageHash]);

                // Only if there are no more pending messages, remove the pending message
                if (state.messages.isEmpty() && state.proofs.isEmpty()) {
                    delete pendingMessages[messageHash];
                }
            } else {
                gateway.handle(payload);
            }

            emit ExecuteMessage(payload, msg.sender);
        } else if (!isMessageProof) {
            pendingMessages[messageHash] = payload;
        }
    }

    /// @dev Governance on Centrifuge Chain can initiate message recovery. After the challenge period,
    ///      the recovery can be executed. If a malign router initiates message recovery, governance on
    ///      Centrifuge Chain can dispute and immediately cancel the recovery, using any other valid router.
    ///
    ///      Only 1 recovery can be outstanding per message hash. If multiple routers fail at the same time,
    //       these will need to be recovered serially (increasing the challenge period for each failed router).
    function _handleRecovery(bytes memory payload) internal {
        if (MessagesLib.messageType(payload) == MessagesLib.Call.InitiateMessageRecovery) {
            (bytes32 messageHash, address router) = MessagesLib.parseInitiateMessageRecovery(payload);
            require(validRouters[msg.sender].id != 0, "RouterAggregator/invalid-router");
            recoveries[messageHash] = Recovery(block.timestamp + RECOVERY_CHALLENGE_PERIOD, router);
            emit InitiateMessageRecovery(messageHash, router);
        } else if (MessagesLib.messageType(payload) == MessagesLib.Call.DisputeMessageRecovery) {
            bytes32 messageHash = MessagesLib.parseDisputeMessageRecovery(payload);
            return _disputeMessageRecovery(messageHash);
        }
    }

    function disputeMessageRecovery(bytes32 messageHash) public auth {
        _disputeMessageRecovery(messageHash);
    }

    function _disputeMessageRecovery(bytes32 messageHash) internal {
        delete recoveries[messageHash];
        emit DisputeMessageRecovery(messageHash);
    }

    function executeMessageRecovery(bytes calldata message) public {
        bytes32 messageHash = keccak256(message);
        Recovery storage recovery = recoveries[messageHash];
        require(recovery.timestamp != 0, "RouterAggregator/message-recovery-not-initiated");
        require(recovery.timestamp <= block.timestamp, "RouterAggregator/challenge-period-has-not-ended");

        _handle(message, validRouters[recovery.router]);
        delete recoveries[messageHash];
    }

    // --- Outgoing ---
    /// @dev Sends 1 message to the first router with the full message, and n-1 messages to the other routers with
    ///      proofs (hash of message). This ensures message uniqueness (can only be executed on the destination once).
    function send(bytes calldata message) public {
        require(msg.sender == address(gateway), "RouterAggregator/only-gateway-allowed-to-call");

        // TODO
        address sender = msg.sender;

        uint256 numRouters = routers.length;
        require(numRouters > 0, "RouterAggregator/not-initialized");

        // uint256 baseCost = messageGas *
        bytes memory proof = abi.encodePacked(uint8(MessagesLib.Call.MessageProof), keccak256(message));
        for (uint256 i; i < numRouters; ++i) {
            RouterLike router = RouterLike(routers[i]);
            router.pay{ value: router.estimate(0) }(sender, i == PRIMARY_ROUTER_ID - 1 ? message : proof);
            router.send(i == PRIMARY_ROUTER_ID - 1 ? message : proof);
        }

        emit SendMessage(message);
    }

    // --- Helpers ---
    function quorum() external view returns (uint8) {
        Router memory router = validRouters[routers[0]];
        return router.quorum;
    }

    function confirmations(bytes32 messageHash)
        external
        view
        returns (uint16[8] memory messages, uint16[8] memory proofs)
    {
        ConfirmationState storage state = _confirmations[messageHash];
        return (state.messages, state.proofs);
    }
}
