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

        bytes memory lpPalletIndex = vm.envBytes("LP_PALLET_INDEX");
        require(lpPalletIndex.length == 1, "LP_PALLET_INDEX not 1 byte");

        bytes memory lpCallIndex = vm.envBytes("LP_CALL_INDEX");
        require(lpCallIndex.length == 1, "LP_CALL_INDEX not 1 byte");

        AxelarXCMRelayer router = new AxelarXCMRelayer(
                address(vm.envAddress("CENTRIFUGE_CHAIN_ORIGIN")),
                address(vm.envAddress("AXELAR_GATEWAY")),
                bytes1(lpPalletIndex),
                bytes1(lpCallIndex)
        );

        router.rely(admin);

        vm.stopBroadcast();
    }
}
