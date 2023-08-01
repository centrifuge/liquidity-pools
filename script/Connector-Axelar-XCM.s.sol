// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.18;

import {ConnectorAxelarXCMRouter} from "src/routers/axelar/XCMRouter.sol";
import "forge-std/Script.sol";

// Script to deploy Connectors with an AxelarXCM router.
contract ConnectorAxelarXCMScript is Script {
    // address(0)[0:20] + keccak("Centrifuge")[21:32]
    bytes32 SALT = 0x000000000000000000000000000000000000000075eb27011b69f002dc094d05;

    function setUp() public {}

    function run() public {
        vm.startBroadcast();

        ConnectorAxelarXCMRouter router = new ConnectorAxelarXCMRouter{ salt: SALT }(
                address(vm.envAddress("CENTRIFUGE_CHAIN_ORIGIN")),
                address(vm.envAddress("AXELAR_GATEWAY")),
                address(vm.envAddress("AXELAR_EVM_ROUTER_ORIGIN"))
        );

        vm.stopBroadcast();
    }
}
