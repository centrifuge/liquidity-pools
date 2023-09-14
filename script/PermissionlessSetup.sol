// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import {PermissionlessRouter} from "test/mock/PermissionlessRouter.sol";
import {InvestmentManager} from "src/InvestmentManager.sol";
import {Deployer, RouterLike} from "./Deployer.sol";

// Script to deploy Liquidity Pools with a permissionless router for testing.
contract PermissionlessSetup is Deployer {
    function run(address _admin) public {
        admin = _admin;
        // Deploy contracts
        deployInvestmentManager();
        PermissionlessRouter router = new PermissionlessRouter();
        wire(address(router));
        RouterLike(address(router)).file("gateway", address(gateway));

        giveAdminAccess();
    }
}
