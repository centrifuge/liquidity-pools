// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import {Auth} from "src/Auth.sol";
import {MessagesLib} from "src/libraries/MessagesLib.sol";

interface GatewayLike {
    function handle(bytes memory message) external;
}

interface RouterLike {
    function send(bytes memory message) external;
}

/// @title  RouterAggregator
/// @notice Routing contract that forwards to multiple routers (1 full message, n-1 proofs)
///         and validates multiple routers have confirmed a message.
///
///         Supports processing multiple duplicate messages in parallel by
///         storing counts of messages and proofs that have been received.
contract RouterAggregator is Auth {
    uint8 public constant MAX_ROUTER_COUNT = 8;
    uint8 public constant PRIMARY_ROUTER_ID = 1;

    GatewayLike public immutable gateway;

    address[] public routers;
    mapping(address router => Router) public validRouters;
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

    // --- Events ---
    event HandleMessage(bytes message, address router);
    event HandleProof(bytes32 messageHash, address router);
    event ExecuteMessage(bytes message, address router);
    event SendMessage(bytes message);
    event RecoverMessage(address router, bytes message);
    event RecoverProof(address router, bytes32 messageHash);
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

            // Enable new routers, setting quorum to number of routers
            uint8 quorum_ = uint8(routers_.length);
            for (uint8 i; i < routers_.length; ++i) {
                // Ids are assigned sequentially starting at 1
                validRouters[routers_[i]] = Router(i + 1, quorum_);
            }

            // Disable old routers that weren't already overridden
            for (uint8 j = uint8(routers_.length); j < routers.length; ++j) {
                delete validRouters[address(routers[j])];
            }

            routers = routers_;
        } else {
            revert("RouterAggregator/file-unrecognized-param");
        }

        emit File(what, routers_);
    }

    // --- Incoming ---
    /// @dev Assumes routers ensure messages cannot be confirmed more than once
    function handle(bytes calldata payload) public {
        Router memory router = validRouters[msg.sender];
        require(router.id != 0, "RouterAggregator/invalid-router");

        if (router.quorum == 1 && !MessagesLib.isMessageProof(payload)) {
            // Special case for gas efficiency
            gateway.handle(payload);
            emit ExecuteMessage(payload, msg.sender);
            return;
        }

        bytes32 messageHash;
        ConfirmationState storage state;
        if (MessagesLib.isMessageProof(payload)) {
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

        if (_countNonZeroValues(state.messages) >= 1 && _countNonZeroValues(state.proofs) >= router.quorum - 1) {
            // Reduce total message confiration count by 1, by finding the first non-zero value
            _decreaseFirstNValues(state.messages, 1, 1);

            // Reduce total proof confiration count by quorum
            _decreaseFirstNValues(state.proofs, router.quorum, 1);

            if (MessagesLib.isMessageProof(payload)) {
                gateway.handle(pendingMessages[messageHash]);

                // Only if there are no more pending messages, remove the pending message
                if (_isEmpty(state.messages) && _isEmpty(state.proofs)) {
                    delete pendingMessages[messageHash];
                }
            } else {
                gateway.handle(payload);
            }

            emit ExecuteMessage(payload, msg.sender);
        } else if (!MessagesLib.isMessageProof(payload)) {
            pendingMessages[messageHash] = payload;
        }
    }

    // --- Outgoing ---
    /// @dev Sends 1 message to the first router with the full message, and n-1 messages to the other routers with
    ///      proofs (hash of message). This ensures message uniqueness (can only be executed on the destination once).
    function send(bytes calldata message) public {
        require(msg.sender == address(gateway), "RouterAggregator/only-gateway-allowed-to-call");

        uint256 numRouters = routers.length;
        require(numRouters > 0, "RouterAggregator/not-initialized");

        bytes memory proof = MessagesLib.formatMessageProof(message);
        for (uint256 i; i < numRouters; ++i) {
            RouterLike(routers[i]).send(i == PRIMARY_ROUTER_ID - 1 ? message : proof);
        }

        emit SendMessage(message);
    }

    /// @dev Recovery method in case the first (primary) router failed to send the message
    function recoverMessage(address router, bytes calldata message) public auth {
        require(validRouters[router].id != 0, "RouterAggregator/invalid-router");
        RouterLike(router).send(message);
        emit RecoverMessage(router, message);
    }

    /// @dev Recovery method in case one of the non-primary routers failed to send the proof
    function recoverProof(address router, bytes32 messageHash) public auth {
        require(validRouters[router].id != 0, "RouterAggregator/invalid-router");
        RouterLike(router).send(MessagesLib.formatMessageProof(messageHash));
        emit RecoverProof(router, messageHash);
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

    function _countNonZeroValues(uint16[8] memory arr) internal pure returns (uint8 count) {
        for (uint256 i; i < arr.length; ++i) {
            if (arr[i] > 0) ++count;
        }
    }

    function _decreaseFirstNValues(uint16[8] storage arr, uint8 numValues, uint16 decrease) internal {
        for (uint256 i; i < arr.length; ++i) {
            if (arr[i] > 0) {
                arr[i] -= decrease;
                numValues--;

                if (numValues == 0) return;
            }
        }
    }

    function _isEmpty(uint16[8] memory arr) internal pure returns (bool) {
        for (uint256 i; i < arr.length; ++i) {
            if (arr[i] > 0) return false;
        }
        return true;
    }
}
