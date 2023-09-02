// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import "./../../src/util/Auth.sol";

interface GatewayLike {
    function handle(bytes memory message) external;
}

contract PermissionlessRouter is Auth {
    GatewayLike public gateway;

    event Send(bytes message);
    event File(bytes32 indexed what, address addr);

    constructor() {
        wards[msg.sender] = 1;
        emit Rely(msg.sender);
    }

    function file(bytes32 what, address gateway_) external {
        if (what == "gateway") {
            gateway = GatewayLike(gateway_);
        } else {
            revert("PermissionlessRouter/file-unrecognized-param");
        }

        emit File(what, gateway_);
    }

    // --- Incoming ---
    function execute(bytes32, string calldata, string calldata, bytes calldata payload) external {
        gateway.handle(payload);
    }

    // --- Outgoing ---
    function send(bytes memory message) public {
        emit Send(message);
    }

    // Added to be ignored in coverage report
    function test() public {}
}
