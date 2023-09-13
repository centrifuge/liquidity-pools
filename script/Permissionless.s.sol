// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import {PermissionlessRouter} from "test/mock/PermissionlessRouter.sol";
import {InvestmentManager} from "src/InvestmentManager.sol";
import {Deployer, RouterLike} from "./Deployer.sol";
import {PermissionlessSetup} from "./permissionlessSetup.sol";

// Script to deploy Liquidity Pools with a permissionless router for testing.
contract PermissionlessScript is PermissionlessSetup {
    function run() public {
        vm.startBroadcast();

        PermissionlessSetup setup = new PermissionlessSetup();
        admin = msg.sender;
        setup.run(admin);

        vm.stopBroadcast();
    }
}
