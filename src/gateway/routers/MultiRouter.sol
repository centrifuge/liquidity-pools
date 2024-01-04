// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import {Auth} from "./../../Auth.sol";

interface GatewayLike {
    function handle(bytes memory message) external;
}

interface RouterLike {
    function send(bytes memory message) external;
}

/// @title  MultiRouter
/// @notice Routing contract that forwards to multiple routers
///         and validates multiple routers have sent a message
contract MultiRouter is Auth {
    uint8 public constant MAX_QUORUM = 5;
    uint8 public constant MAX_ROUTER_COUNT = 6;

    GatewayLike public gateway;

    uint8 public quorum;
    address[] public routers;
    mapping(address router => bool isValid) public validRouters;

    /// @dev This router does not use unique message IDs. If there are multiple
    ///      messages with the exact same payload, the received counts will be 
    ///      increased beyond the router length. E.g. for 2 messages, a router length
    ///      of 4 and a quorum of 3, both messages can be executed if the received
    ///      count exeeds 6.
    mapping(bytes32 messageHash => uint8) public executedCount;
    mapping(bytes32 messageHash => uint8) public receivedCount;
    mapping(bytes32 messageHash => mapping(address router => uint receivedCount)) public receivedCountByRouter;

    // --- Events ---
    event File(bytes32 indexed what, uint8 quorum);
    event File(bytes32 indexed what, address[] routers);

    constructor() {
        wards[msg.sender] = 1;
        emit Rely(msg.sender);
    }

    // --- Administration ---
    function file(bytes32 what, uint8 quorum_) external auth {
        if (what == "quorum") {
            require(quorum_ <= MAX_QUORUM, "MultiRouter/exceeds-max-quorum");
            quorum = quorum_;
        } else {
            revert("MultiRouter/file-unrecognized-param");
        }

        emit File(what, quorum_);
    }

    function file(bytes32 what, address[] calldata routers_) external auth {
        if (what == "routers") {
            require(routers_.length <= MAX_ROUTER_COUNT, "MultiRouter/exceeds-max-router-count");

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
            revert("MultiRouter/file-unrecognized-param");
        }

        emit File(what, routers_);
    }

    // --- Incoming ---
    function execute(bytes calldata payload) public {
        require(validRouters[msg.sender] == true, "MultiRouter/invalid-router");
        bytes32 messageHash = keccak256(payload);

        if (receivedByRouter[messageHash][msg.sender] == false) {
            uint8 oldReceivedCount = receivedCount[messageHash];
            if (oldReceivedCount + 1 >= quorum) {
                // Quorum reached, execute payload
                gateway.handle(payload);
            } else {
                // Quorum not yet reached, increase count
                receivedCount[messageHash] = oldReceivedCount + 1;
                receivedByRouter[messageHash][msg.sender] = true;
            }
        }
    }

    // --- Outgoing ---
    function send(bytes calldata message) public {
        require(msg.sender == address(gateway), "MultiRouter/only-gateway-allowed-to-call");
        for (uint256 i = 0; i < routers.length; ++i) {
            RouterLike(routers[i]).send(message);
        }
    }
}
