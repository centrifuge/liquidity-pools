// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.18;

import {AxelarXCMRouter} from "src/gateway/routers/axelar/XCMRouter.sol";
import {Deployer} from "./Deployer.sol";

// Script to deploy Liquidity Pools with an Axelar router.
contract AxelarXCMScript is Deployer {
    // address(0)[0:20] + keccak("Centrifuge")[21:32]
    bytes32 SALT = 0x000000000000000000000000000000000000000075eb27011b69f002dc094d05;

    function setUp() public {}

    function run() public {
        vm.startBroadcast();

        admin = vm.envAddress("ADMIN");

        deployInvestmentManager();
        AxelarXCMRouter router = new AxelarXCMRouter(
                address(vm.envAddress("CENTRIFUGE_CHAIN_ORIGIN")),
                address(vm.envAddress("AXELAR_GATEWAY")),
                address(vm.envAddress("AXELAR_EVM_ROUTER"))
        );
        wire(address(router));

        giveAdminAccess();
        removeDeployerAccess(address(router));

        vm.stopBroadcast();
    }
}
