// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import {AxelarXCMRelayer} from "src/gateway/routers/axelar/XCMRelayer.sol";
import {Deployer} from "./Deployer.sol";

// Script to deploy Axelar over XCM relayer.
contract AxelarXCMRelayerScript is Deployer {
    function setUp() public {}

    function run() public {
        vm.startBroadcast();

        admin = vm.envAddress("ADMIN");

        uint8 lpPalletIndex = uint8(vm.envUint("LP_PALLET_INDEX"));
        uint8 lpCallIndex = uint8(vm.envUint("LP_CALL_INDEX"));
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
