// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.18;

import {AxelarEVMRouter} from "src/routers/axelar/EVMRouter.sol";
import {Deployer} from "./Deployer.sol";

// Script to deploy Liquidity Pools with an Axelar router.
contract AxelarEVMScript is Deployer {
    // address(0)[0:20] + keccak("Centrifuge")[21:32]
    bytes32 SALT = 0x000000000000000000000000000000000000000075eb27011b69f002dc094d05;

    function setUp() public {}

    function run() public {
        vm.startBroadcast();

        admin = vm.envAddress("ADMIN");

        address investmentManager = deployInvestmentManager();
        AxelarEVMRouter router = new AxelarEVMRouter(
                investmentManager,
                address(vm.envAddress("AXELAR_GATEWAY"))
        );
        wire(address(router));

        giveAdminAccess();
        removeDeployerAccess(address(router));

        vm.stopBroadcast();
    }
}
