// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import "forge-std/Test.sol";
import {InvestmentManager} from "src/InvestmentManager.sol";
import {Gateway} from "src/gateway/Gateway.sol";
import {Auth} from "src/Auth.sol";
import "./Mock.sol";

interface GatewayLike {
    function handle(bytes memory message) external;
}

contract MockRouter is Auth, Mock {
    GatewayLike public gateway;

    mapping(bytes => uint256) public sent;

    constructor() {
        wards[msg.sender] = 1;
    }

    function file(bytes32 what, address addr) external {
        if (what == "gateway") {
            gateway = GatewayLike(addr);
        } else {
            revert("MockRouter/file-unrecognized-param");
        }
    }

    function execute(bytes memory _message) external {
        GatewayLike(gateway).handle(_message);
    }

    function send(bytes memory message) public {
        values_bytes["send"] = message;
        sent[message]++;
    }

    // Added to be ignored in coverage report
    function test() public {}
}
