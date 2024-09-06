// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.26;

import {PermissionlessAdapter} from "test/mocks/PermissionlessAdapter.sol";
import {InvestmentManager} from "src/InvestmentManager.sol";
import {Deployer} from "script/Deployer.sol";

// Script to deploy Liquidity Pools with a permissionless adapter for testing.
contract PermissionlessScript is Deployer {
    function setUp() public {}

    function run() public {
        vm.startBroadcast();
        address[] memory _adapters = new address[](1);
        _adapters[0] = address(new PermissionlessAdapter(address(gateway)));
        deploy(msg.sender, msg.sender, _adapters);

        vm.stopBroadcast();
    }
}
