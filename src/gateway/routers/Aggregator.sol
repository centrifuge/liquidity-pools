// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import {Auth} from "src/Auth.sol";
import {ArrayLib} from "src/libraries/ArrayLib.sol";
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

    constructor(address gateway_) {
        gateway = GatewayLike(gateway_);

        wards[msg.sender] = 1;
        emit Rely(msg.sender);
    }

    // --- Administration ---
    /// @inheritdoc IAggregator
    function file(bytes32 what, address[] calldata routers_) external auth {
        if (what == "routers") {
            require(routers_.length <= MAX_ROUTER_COUNT, "Aggregator/exceeds-max-router-count");

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
            revert("Aggregator/file-unrecognized-param");
        }

        emit File(what, routers_);
    }

    // --- Incoming ---
    /// @inheritdoc IAggregator
    function handle(bytes calldata payload) public {
        Router memory router = validRouters[msg.sender];
        require(router.id != 0, "Aggregator/invalid-router");
        _handle(payload, router);
    }

    function _handle(bytes calldata payload, Router memory router) internal {
        if (MessagesLib.isRecoveryMessage(payload)) {
            require(routers.length > 1, "Aggregator/no-recovery-with-one-router-allowed");
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
            require(router.id != 1, "RouterAggregator/non-proof-router");
            messageHash = MessagesLib.parseMessageProof(payload);
            state = _confirmations[messageHash];
            state.proofs[router.id - 1]++;

            emit HandleProof(messageHash, msg.sender);
        } else {
            require(router.id == 1, "RouterAggregator/non-message-router");
            messageHash = keccak256(payload);
            state = _confirmations[messageHash];
            state.messages[router.id - 1]++;

            emit HandleMessage(payload, msg.sender);
        }

        if (state.messages.countNonZeroValues() >= 1 && state.proofs.countNonZeroValues() >= router.quorum - 1) {
            // Reduce total message confirmation count by 1
            state.messages.decreaseFirstNValues(1);

            // Reduce total proof confiration count by quorum - 1
            state.proofs.decreaseFirstNValues(router.quorum - 1);

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

    function _handleRecovery(bytes memory payload) internal {
        if (MessagesLib.messageType(payload) == MessagesLib.Call.InitiateMessageRecovery) {
            (bytes32 messageHash, address router) = MessagesLib.parseInitiateMessageRecovery(payload);
            require(validRouters[msg.sender].id != 0, "Aggregator/invalid-router");
            recoveries[messageHash] = Recovery(block.timestamp + RECOVERY_CHALLENGE_PERIOD, router);
            emit InitiateMessageRecovery(messageHash, router);
        } else if (MessagesLib.messageType(payload) == MessagesLib.Call.DisputeMessageRecovery) {
            bytes32 messageHash = MessagesLib.parseDisputeMessageRecovery(payload);
            return _disputeMessageRecovery(messageHash);
        }
    }

    /// @inheritdoc IAggregator
    function disputeMessageRecovery(bytes32 messageHash) public auth {
        _disputeMessageRecovery(messageHash);
    }

    function _disputeMessageRecovery(bytes32 messageHash) internal {
        delete recoveries[messageHash];
        emit DisputeMessageRecovery(messageHash);
    }

    /// @inheritdoc IAggregator
    function executeMessageRecovery(bytes calldata message) public {
        bytes32 messageHash = keccak256(message);
        Recovery storage recovery = recoveries[messageHash];
        require(recovery.timestamp != 0, "Aggregator/message-recovery-not-initiated");
        require(recovery.timestamp <= block.timestamp, "Aggregator/challenge-period-has-not-ended");

        _handle(message, validRouters[recovery.router]);
        delete recoveries[messageHash];
    }

    // --- Outgoing ---
    /// @inheritdoc IAggregator
    function send(bytes calldata message) public {
        require(msg.sender == address(gateway), "Aggregator/only-gateway-allowed-to-call");

        uint256 numRouters = routers.length;
        require(numRouters > 0, "Aggregator/not-initialized");

        bytes memory proof = abi.encodePacked(uint8(MessagesLib.Call.MessageProof), keccak256(message));
        for (uint256 i; i < numRouters; ++i) {
            RouterLike(routers[i]).send(i == PRIMARY_ROUTER_ID - 1 ? message : proof);
        }

        emit SendMessage(message);
    }

    // --- Helpers ---
    /// @inheritdoc IAggregator
    function quorum() external view returns (uint8) {
        Router memory router = validRouters[routers[0]];
        return router.quorum;
    }

    /// @inheritdoc IAggregator
    function confirmations(bytes32 messageHash)
        external
        view
        returns (uint16[8] memory messages, uint16[8] memory proofs)
    {
        ConfirmationState storage state = _confirmations[messageHash];
        return (state.messages, state.proofs);
    }
}
