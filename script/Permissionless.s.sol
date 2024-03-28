// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import {PermissionlessRouter} from "test/mocks/PermissionlessRouter.sol";
import {InvestmentManager} from "src/InvestmentManager.sol";
import {Deployer, RouterLike} from "./Deployer.sol";

// Script to deploy Liquidity Pools with a permissionless router for testing.
contract PermissionlessScript is Deployer {
    function setUp() public {}

    function run() public {
        vm.startBroadcast();

        admin = msg.sender;
        pausers = [msg.sender];

        deploy(msg.sender);
        PermissionlessRouter router = new PermissionlessRouter(address(aggregator));
        wire(address(router));

        giveAdminAccess();

        vm.stopBroadcast();
    }
}
