// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import {PermissionlessRouter} from "test/mocks/PermissionlessRouter.sol";
import {InvestmentManager} from "src/InvestmentManager.sol";
import {Deployer, RouterLike} from "script/Deployer.sol";

// Script to deploy Liquidity Pools with a permissionless router for testing.
contract PermissionlessScript is Deployer {
    function setUp() public {}

    function run() public {
        vm.startBroadcast();

        adminSafe = msg.sender;

        deploy(msg.sender);
        PermissionlessRouter router = new PermissionlessRouter(address(gateway));
        wire(address(router));

        vm.stopBroadcast();
    }
}
