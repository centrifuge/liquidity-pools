// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import {Auth} from "./../../Auth.sol";
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
    /// @dev Soft limitation
    uint8 public constant MAX_QUORUM = 6;

    /// @dev Hard limitation because of use of bit packing in confirmations storage
    uint8 public constant MAX_ROUTER_COUNT = 8;

    GatewayLike public gateway;

    uint8 public quorum;
    address[] public routers;
    mapping(address router => uint8) public routerIds;
    mapping(address router => bool isValid) public validRouters;

    /// @dev This router does not use unique message IDs. If there are multiple
    ///      messages with the exact same payload, the received counts will be
    ///      increased beyond the router length. E.g. for 2 messages, a router length
    ///      of 4 and a quorum of 3, both messages can be executed if the received
    ///      count exeeds 6.
    ///
    ///      A single bytes32 value can store 8 uint32 values. type(uint32).max = 4,294,967,295
    ///      Therefore, at most 4,294,967,295 messages can be unprocessed, meaning confirmed by
    ///      1 router but not by others.
    mapping(bytes32 messageHash => uint256) public confirmations;

    // --- Events ---
    event File(bytes32 indexed what, address gateway);
    event File(bytes32 indexed what, uint8 quorum);
    event File(bytes32 indexed what, address router, uint8 id);
    event File(bytes32 indexed what, address[] routers);

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

    function file(bytes32 what, uint8 quorum_) external auth {
        if (what == "quorum") {
            require(quorum_ <= MAX_QUORUM, "RouterAggregator/exceeds-max-quorum");
            quorum = quorum_;
        } else {
            revert("RouterAggregator/file-unrecognized-param");
        }

        emit File(what, quorum_);
    }

    /// @dev Ward needs to ensure router IDs are not reused
    function file(bytes32 what, address router, uint8 id) external auth {
        if (what == "routerId") {
            require(id < MAX_ROUTER_COUNT, "RouterAggregator/exceeds-max-router-count");
            routerIds[router] = id;
        } else {
            revert("RouterAggregator/file-unrecognized-param");
        }

        emit File(what, router, id);
    }

    function file(bytes32 what, address[] calldata routers_) external auth {
        if (what == "routers") {
            require(routers_.length <= MAX_ROUTER_COUNT, "RouterAggregator/exceeds-max-router-count");

            // Disable old routers
            // TODO: try to combine with loop later to save storage reads/writes
            for (uint256 i = 0; i < routers.length; ++i) {
                validRouters[address(routers[i])] = false;
            }

            // Enable new routers
            routers = routers_;
            for (uint256 i = 0; i < routers_.length; ++i) {
                validRouters[routers_[i]] = true;
            }
        } else {
            revert("RouterAggregator/file-unrecognized-param");
        }

        emit File(what, routers_);
    }

    // --- Incoming ---
    /// @dev Assumes routers ensure messages cannot be confirmed more than once
    function execute(bytes calldata payload) public {
        require(validRouters[msg.sender] == true, "RouterAggregator/invalid-router");

        bytes32 messageHash = keccak256(payload);
        uint256 messageConfirmations = confirmations[messageHash];

        uint8 routerId = routerIds[msg.sender];
        messageConfirmations =
            packUint32(messageConfirmations, routerId, unpackUint32(messageConfirmations, routerId) + 1);

        if (countPackedUint32NonZero(messageConfirmations) >= quorum) {
            messageConfirmations = decreasePackedUint32(messageConfirmations, 1);
            gateway.handle(payload);
        }
    }

    // TODO: move to BytesLib, add tests
    function packUint32(uint256 packed, uint8 index, uint32 value) internal pure returns (uint256) {
        return packed ^ (value << (index * 4)); // 1 uint32 = 4 bits
    }

    function unpackUint32(uint256 packed, uint8 index) internal pure returns (uint32) {
        uint256 result = packed & (0xFFFFFF << index);
        return uint32(result >> index);
    }

    function countPackedUint32NonZero(uint256 packed) internal pure returns (uint8 count) {
        for (uint8 i = 0; i < 255; i += 3) {
            if (packed & (0xFFFFFF) >= 1) {
                count++;
            }

            packed >>= 4; // 1 uint32 = 4 bits
        }
    }

    function decreasePackedUint32(uint256 packed, uint32 decrease) internal view returns (uint256) {
        // TODO: rewrite using direct bit shifting

        for (uint8 i = 0; i < 8; i++) {
            uint32 value = unpackUint32(packed, i);
            console.log(i, value);
            if (value > 0) packed = packUint32(packed, i, value - decrease);
        }

        return packed;
    }

    // --- Outgoing ---
    function send(bytes calldata message) public {
        require(msg.sender == address(gateway), "RouterAggregator/only-gateway-allowed-to-call");
        for (uint256 i = 0; i < routers.length; ++i) {
            RouterLike(routers[i]).send(message);
        }
    }
}
