// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.18;

import {AxelarXCMRelayer} from "src/gateway/routers/axelar/XCMRelayer.sol";
import {Deployer} from "./Deployer.sol";

// Script to deploy Axelar over XCM relayer.
contract AxelarXCMRelayerScript is Deployer {
    function setUp() public {}

    function run() public {
        vm.startBroadcast();

        admin = vm.envAddress("ADMIN");

        AxelarXCMRelayer router = new AxelarXCMRelayer(
                address(vm.envAddress("CENTRIFUGE_CHAIN_ORIGIN")),
                address(vm.envAddress("AXELAR_GATEWAY")),
                address(vm.envAddress("AXELAR_EVM_ROUTER"))
        );

        router.rely(admin);

        vm.stopBroadcast();
    }
}
