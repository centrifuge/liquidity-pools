// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.18;
pragma abicoder v2;

interface GatewayLike {
    function handle(bytes memory message) external;
}

contract PermissionlessRouter {
    mapping(address => uint256) public wards;
    GatewayLike public gateway;

    event Rely(address indexed user);
    event Deny(address indexed user);
    event Send(bytes message);
    event File(bytes32 indexed what, address addr);

    constructor() {
        wards[msg.sender] = 1;
        emit Rely(msg.sender);
    }

    modifier auth() {
        require(wards[msg.sender] == 1, "PermissionlessRouter/not-authorized");
        _;
    }

    function file(bytes32 what, address gateway_) external {
        if (what == "gateway") {
            gateway = GatewayLike(gateway_);
        } else {
            revert("PermissionlessRouter/file-unrecognized-param");
        }

        emit File(what, gateway_);
    }

    // --- Administration ---
    function rely(address user) external auth {
        wards[user] = 1;
        emit Rely(user);
    }

    function deny(address user) external auth {
        wards[user] = 0;
        emit Deny(user);
    }

    // --- Incoming ---
    function execute(bytes32, string calldata, string calldata, bytes calldata payload) external {
        gateway.handle(payload);
    }

    // --- Outgoing ---
    function send(bytes memory message) public {
        emit Send(message);
    }
}
