// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.26;

import {AxelarAdapter} from "src/gateway/adapters/axelar/Adapter.sol";
import {Deployer, Deployment} from "script/Deployer.sol";
import {DeploymentManager} from "test/utils/DeploymentManager.sol";

// Script to deploy Liquidity Pools with an Axelar Adapter.
contract AxelarScript is Deployer {
    using DeploymentManager for Deployment;

    function setUp() public {}

    function run() public {
        vm.startBroadcast();

        address[] memory _adapters = new address[](1);
        _adapters[0] = address(
            new AxelarAdapter(
                address(gateway), address(vm.envAddress("AXELAR_GATEWAY")), address(vm.envAddress("AXELAR_GAS_SERVICE"))
            )
        );

        address _admin = vm.envOr("ADMIN", address(0));

        Deployment memory deployment_ = deploy(msg.sender, _admin, _adapters);
        // TODO We can deploy multiple adapters so not only this one, so this have to accepts juts adapter configuration
        deployment_.saveAsJson("AxelarAdapter");
        removeDeployerAccess();

        vm.stopBroadcast();
    }
}
