// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import "./../../src/Auth.sol";

interface GatewayLike {
    function handle(bytes memory message) external;
}

contract PermissionlessRouter is Auth {
    GatewayLike public immutable gateway;

    event Send(bytes message);

    constructor(address gateway_) {
        gateway = GatewayLike(gateway_);

        wards[msg.sender] = 1;
        emit Rely(msg.sender);
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
