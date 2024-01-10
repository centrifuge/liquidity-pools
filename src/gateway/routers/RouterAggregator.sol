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
    uint8 public constant MAX_QUORUM = 3;
    uint8 public constant MAX_ROUTER_COUNT = 4;

    GatewayLike public gateway;

    uint8 public quorum;
    address[] public routers;
    mapping(address router => uint8) public routerIds;
    mapping(address router => bool isValid) public validRouters;

    /// @dev This router does not use unique message IDs. If there are multiple
    ///      messages with the exact same payload, the received counts will be
    ///      increased beyond the router length. E.g. for 2 messages, a router length
    ///      of 4 and a quorum of 3, both messages can be executed if the received
    ///      count exeeds 6. The counts are added across payloads and proofs.
    ///
    ///      A single bytes32 value can store 4 uint64 values
    struct ConfirmationState {
        uint64[4] payloads;
        uint64[4] proofs;
        // If 1 or more proofs are received before full payload,
        // store here for later execution
        bytes fullPayload;
    }

    // TODO: scale up to 8 routers with uint32
    struct Counts {
        uint64 router0;
        uint64 router1;
        uint64 router2;
        uint64 router3;
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
            for (uint8 i = 0; i < routers.length; ++i) {
                validRouters[address(routers[i])] = false;
            }

            // Enable new routers and set quorum
            routers = routers_;
            for (uint8 i = 0; i < routers_.length; ++i) {
                validRouters[routers_[i]] = true;
                routerIds[routers_[i]] = i;
            }
            quorum = quorum_;
        } else {
            revert("RouterAggregator/file-unrecognized-param");
        }

        emit File(what, routers_, quorum_);
    }

    // --- Incoming ---
    /// @dev Assumes routers ensure messages cannot be confirmed more than once
    function execute(bytes calldata payload) public {
        require(validRouters[msg.sender] == true, "RouterAggregator/invalid-router");
        uint8 routerId = routerIds[msg.sender];

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

        uint8 totalPayloads = countNonZeroValues(state.payloads);
        uint8 totalProofs = countNonZeroValues(state.proofs);

        if (totalPayloads + totalProofs >= quorum && totalPayloads >= 1) {
            decreaseValues(state.payloads, 1);
            decreaseValues(state.proofs, 1);

            if (MessagesLib.isMessageProof(payload)) {
                gateway.handle(state.fullPayload);
            } else {
                gateway.handle(payload);
            }
        } else if (!MessagesLib.isMessageProof(payload)) {
            state.fullPayload = payload;
        }
    }

    function countNonZeroValues(uint64[4] memory arr) internal pure returns (uint8 count) {
        for (uint256 i = 0; i < arr.length; ++i) {
            if (arr[i] > 0) ++count;
        }
    }

    function decreaseValues(uint64[4] storage arr, uint64 decrease) internal {
        for (uint256 i = 0; i < arr.length; ++i) {
            if (arr[i] > 0) arr[i] -= decrease;
        }
    }

    // --- Outgoing ---
    function send(bytes calldata message) public {
        require(msg.sender == address(gateway), "RouterAggregator/only-gateway-allowed-to-call");
        for (uint256 i = 0; i < routers.length; ++i) {
            RouterLike(routers[i]).send(message);
        }
    }
}
