// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import {PermissionlessAdapter} from "test/mocks/PermissionlessAdapter.sol";
import {InvestmentManager} from "src/InvestmentManager.sol";
import {Deployer, AdapterLike} from "script/Deployer.sol";

// Script to deploy Liquidity Pools with a permissionless adapter for testing.
contract PermissionlessScript is Deployer {
    function setUp() public {}

    function run() public {
        vm.startBroadcast();

        adminSafe = msg.sender;

        deploy(msg.sender);
        PermissionlessAdapter adapter = new PermissionlessAdapter(address(gateway));
        wire(address(adapter));

        vm.stopBroadcast();
    }
}
