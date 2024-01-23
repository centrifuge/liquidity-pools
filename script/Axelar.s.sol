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

        deployInvestmentManager(msg.sender);
        AxelarRouter router = new AxelarRouter(address(vm.envAddress("AXELAR_GATEWAY")));
        wire(address(router));
        router.file("gateway", address(gateway));

        giveAdminAccess();
        removeDeployerAccess(address(router), msg.sender);

        vm.stopBroadcast();
    }
}
