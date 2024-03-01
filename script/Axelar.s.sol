// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import {AxelarRouter} from "src/gateway/routers/axelar/Router.sol";
import {ERC20} from "src/token/ERC20.sol";
import {Deployer, RouterLike} from "./Deployer.sol";
import {AxelarForwarder} from "src/gateway/routers/axelar/Forwarder.sol";

interface LiquidityPoolLike {
    function requestDeposit(uint256 assets, address owner) external;
}

// Script to deploy Liquidity Pools with an Axelar router.
contract AxelarScript is Deployer {
    function setUp() public {}

    function run() public {
        vm.startBroadcast();

        admin = vm.envAddress("ADMIN");
        pausers = vm.envAddress("PAUSERS", ",");

        deploy(msg.sender);
        AxelarRouter router = new AxelarRouter(
            address(aggregator), address(vm.envAddress("AXELAR_GATEWAY")), address(vm.envAddress("AXELAR_GAS_SERVICE"))
        );
        wire(address(router));

        giveAdminAccess();
        removeDeployerAccess(address(router), msg.sender);

        vm.stopBroadcast();
    }
}
