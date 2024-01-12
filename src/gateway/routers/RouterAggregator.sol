// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import {Auth} from "./../../Auth.sol";
import {MessagesLib} from "src/libraries/MessagesLib.sol";
import "forge-std/Console.sol";

interface GatewayLike {
    function handle(bytes memory message) external;
}

interface RouterLike {
    function send(bytes memory message) external;
}

/// @title  RouterAggregator
/// @notice Routing contract that forwards to multiple routers (1 payload, n-1 proofs)
///         and validates multiple routers have confirmed a message
contract RouterAggregator is Auth {
    uint8 public constant MIN_QUORUM = 1;
    uint8 public constant MAX_QUORUM = 6;

    // Array of 8 is used to store paylods & proofs, but index 0 is reserved
    // as this is the default value and therefore used to detect invalid routers
    uint8 public constant MAX_ROUTER_COUNT = 7;

    GatewayLike public immutable gateway;

    uint8 public quorum;
    address[] public routers;

    struct Router {
        // We pack each router struct with the quorum to reduce SLOADs on handle
        uint8 id;
        uint8 quorum;
    }

    mapping(address router => Router) public validRouters;

    struct ConfirmationState {
        // Counts are stored as integers (instead of boolean values) to accommodate duplicate
        // messages (e.g. two investments from the same user with the same amount) being
        // processed in parallel. The entire struct is packed in a single bytes32 slot.
        // Max uint16 = 65,535 so at most 65,535 duplicate messages can be processed in parallel.
        uint16[8] payloads;
        uint16[8] proofs;
    }

    mapping(bytes32 messageHash => ConfirmationState) internal _confirmations;

    // If 1 or more proofs are received before full payload,
    // store here for later execution
    mapping(bytes32 messageHash => bytes) public storedPayload;

    // --- Events ---
    event File(bytes32 indexed what, address[] routers, uint8 quorum);

    constructor(address gateway_) {
        gateway = GatewayLike(gateway_);

        wards[msg.sender] = 1;
        emit Rely(msg.sender);
    }

    // --- Administration ---
    function file(bytes32 what, address[] calldata routers_, uint8 quorum_) external auth {
        if (what == "routers") {
            require(routers_.length <= MAX_ROUTER_COUNT, "RouterAggregator/exceeds-max-router-count");
            require(quorum_ >= MIN_QUORUM, "RouterAggregator/less-than-min-quorum");
            require(quorum_ <= MAX_QUORUM, "RouterAggregator/exceeds-max-quorum");
            require(quorum_ <= routers_.length, "RouterAggregator/quorum-exceeds-num-routers");

            // Disable old routers
            // TODO: try to combine with loop later to save storage reads/writes
            for (uint8 i = 0; i < routers.length; ++i) {
                delete validRouters[address(routers[i])];
            }

            // Enable new routers and set quorum
            routers = routers_;
            for (uint8 i = 0; i < routers_.length; ++i) {
                // Ids are assigned sequentially starting at 1
                validRouters[routers_[i]] = Router(i + 1, quorum_);
            }
        } else {
            revert("RouterAggregator/file-unrecognized-param");
        }

        emit File(what, routers_, quorum_);
    }

    // --- Incoming ---
    /// @dev Assumes routers ensure messages cannot be confirmed more than once
    function handle(bytes calldata payload) public {
        Router memory router = validRouters[msg.sender];
        require(router.id != 0, "RouterAggregator/invalid-router");

        if (router.quorum == 1 && !MessagesLib.isMessageProof(payload)) {
            // Special case for gas efficiency
            gateway.handle(payload);
            return;
        }

        bytes32 messageHash;
        ConfirmationState storage state;
        if (MessagesLib.isMessageProof(payload)) {
            messageHash = MessagesLib.parseMessageProof(payload);
            state = _confirmations[messageHash];
            state.proofs[router.id]++;
        } else {
            messageHash = keccak256(payload);
            state = _confirmations[messageHash];
            state.payloads[router.id]++;
        }

        uint8 totalPayloads = _countNonZeroValues(state.payloads);
        uint8 totalProofs = _countNonZeroValues(state.proofs);

        if (totalPayloads + totalProofs >= router.quorum && totalPayloads >= 1) {
            _decreaseValues(state.payloads, 1);
            // TODO: this should reduce (quorum - 1) of the highest values, not all, by one
            _decreaseValues(state.proofs, 1);

            if (MessagesLib.isMessageProof(payload)) {
                gateway.handle(storedPayload[messageHash]);
                delete storedPayload[messageHash];
            } else {
                gateway.handle(payload);
            }
        } else if (!MessagesLib.isMessageProof(payload)) {
            storedPayload[messageHash] = payload;
        }
    }

    // --- Outgoing ---
    /// @dev Sends 1 message to the first router with full payload, and n-1 messages to the other routers with
    ///      proofs (hash of message). This ensures message uniqueness (can only be executed on the destination once).
    function send(bytes calldata message) public {
        require(msg.sender == address(gateway), "RouterAggregator/only-gateway-allowed-to-call");
        _send(message, 0);
    }

    /// @dev Recovery method in case the first (primary) router failed to send a message
    ///      or more than (num routers - quorum) failed to send the proof
    function recover(bytes calldata message, uint8 primaryRouterId) public auth {
        // TODO: invalidate previous full payload message by sending `InvalidateMessageId` message
        // with router specific message id passed as arg to `resend`?
        _send(message, primaryRouterId);
    }

    function _send(bytes calldata message, uint8 primaryRouterId) internal {
        bytes memory proofMessage = MessagesLib.formatMessageProof(message);
        for (uint256 i = 0; i < routers.length; ++i) {
            RouterLike(routers[i]).send(i == primaryRouterId ? message : proofMessage);
        }
    }

    // --- Helpers ---
    function confirmations(bytes32 messageHash)
        public
        view
        returns (uint16[8] memory payloads, uint16[8] memory proofs)
    {
        ConfirmationState storage state = _confirmations[messageHash];
        payloads = state.payloads;
        proofs = state.proofs;
    }

    function _countNonZeroValues(uint16[8] memory arr) internal pure returns (uint8 count) {
        for (uint256 i = 0; i < arr.length; ++i) {
            if (arr[i] > 0) ++count;
        }
    }

    function _decreaseValues(uint16[8] storage arr, uint16 decrease) internal {
        for (uint256 i = 0; i < arr.length; ++i) {
            if (arr[i] > 0) arr[i] -= decrease;
        }
    }
}
