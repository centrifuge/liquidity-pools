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
/// @notice Routing contract that forwards to multiple routers
///         and validates multiple routers have confirmed a message
contract RouterAggregator is Auth {
    uint8 public constant MAX_QUORUM = 6;

    // Array of 8 is used to store paylods & proofs, but index 0 is reserved
    // as this is the default value and therefore used to detect invalid routers
    uint8 public constant MAX_ROUTER_COUNT = 7;

    GatewayLike public gateway;

    uint8 public quorum;
    address[] public routers;
    mapping(address router => uint8 id) public validRouters;

    /// @dev This router does not use unique message IDs. If there are multiple
    ///      messages with the exact same payload, the received counts will be
    ///      increased beyond the router length. E.g. for 2 messages, a router length
    ///      of 4 and a quorum of 3, both messages can be executed if the received
    ///      count exeeds 6. The counts are added across payloads and proofs.
    struct ConfirmationState {
        // Each uint32[8] value is packed in a single bytes32 slot
        uint32[8] payloads;
        uint32[8] proofs;
        // If 1 or more proofs are received before full payload,
        // store here for later execution
        bytes fullPayload;
    }

    mapping(bytes32 messageHash => ConfirmationState) public confirmations;

    // --- Events ---
    event File(bytes32 indexed what, address gateway);
    event File(bytes32 indexed what, address[] routers, uint8 quorum);

    constructor() {
        wards[msg.sender] = 1;
        emit Rely(msg.sender);
    }

    // --- Administration ---
    function file(bytes32 what, address data) external auth {
        if (what == "gateway") {
            gateway = GatewayLike(data);
        } else {
            revert("RouterAggregator/file-unrecognized-param");
        }

        emit File(what, data);
    }

    function file(bytes32 what, address[] calldata routers_, uint8 quorum_) external auth {
        if (what == "routers") {
            require(routers_.length <= MAX_ROUTER_COUNT, "RouterAggregator/exceeds-max-router-count");
            require(quorum_ <= MAX_QUORUM, "RouterAggregator/exceeds-max-quorum");

            // Disable old routers
            // TODO: try to combine with loop later to save storage reads/writes
            for (uint8 i = 1; i <= routers.length; ++i) {
                validRouters[address(routers[i])] = 0;
            }

            // Enable new routers and set quorum
            routers = routers_;
            for (uint8 i = 0; i < routers_.length; ++i) {
                validRouters[routers_[i]] = i + 1;
            }
            quorum = quorum_;
        } else {
            revert("RouterAggregator/file-unrecognized-param");
        }

        emit File(what, routers_, quorum_);
    }

    // --- Incoming ---
    /// @dev Assumes routers ensure messages cannot be confirmed more than once
    function handle(bytes calldata payload) public {
        uint8 routerId = validRouters[msg.sender];
        require(routerId != 0, "RouterAggregator/invalid-router");

        ConfirmationState storage state;
        if (MessagesLib.isMessageProof(payload)) {
            bytes32 messageHash = MessagesLib.parseMessageProof(payload);
            state = confirmations[messageHash];
            state.proofs[routerId]++;
        } else {
            bytes32 messageHash = keccak256(payload);
            state = confirmations[messageHash];
            state.payloads[routerId]++;
        }

        uint8 totalPayloads = _countNonZeroValues(state.payloads);
        uint8 totalProofs = _countNonZeroValues(state.proofs);

        if (totalPayloads + totalProofs >= quorum && totalPayloads >= 1) {
            _decreaseValues(state.payloads, 1);
            _decreaseValues(state.proofs, 1);

            if (MessagesLib.isMessageProof(payload)) {
                gateway.handle(state.fullPayload);
            } else {
                gateway.handle(payload);
            }
        } else if (!MessagesLib.isMessageProof(payload)) {
            state.fullPayload = payload;
        }
    }

    // --- Outgoing ---
    // TODO: how to choose which router for the payload and which for proofs,
    // and how to handle recovery if the payload router fails?
    //
    // Can we allow resending the payload over another router, only by the initial user or some kind of admin?
    function send(bytes calldata message) public {
        require(msg.sender == address(gateway), "RouterAggregator/only-gateway-allowed-to-call");

        // Send full payload once
        RouterLike(routers[0]).send(message);

        // Send proofs n-1 times
        for (uint256 i = 1; i < routers.length; ++i) {
            RouterLike(routers[i]).send(MessagesLib.formatMessageProof(message));
        }
    }

    // --- Helpers ---
    function _countNonZeroValues(uint32[8] memory arr) internal pure returns (uint8 count) {
        for (uint256 i = 0; i < arr.length; ++i) {
            if (arr[i] > 0) ++count;
        }
    }

    function _decreaseValues(uint32[8] storage arr, uint32 decrease) internal {
        for (uint256 i = 0; i < arr.length; ++i) {
            if (arr[i] > 0) arr[i] -= decrease;
        }
    }
}
