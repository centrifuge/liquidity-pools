// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import {AxelarForwarder} from "../src/gateway/routers/axelar/Forwarder.sol";
import "@sphinx-labs/contracts/SphinxPlugin.sol";
import "forge-std/Script.sol";

// Script to deploy Axelar over XCM relayer.
contract ForwarderScript is Script, Sphinx {
    function setUp() public {}

    function configureSphinx() public override {
        sphinxConfig.owners = [address(0x423420Ae467df6e90291fd0252c0A8a637C1e03f)];
        sphinxConfig.orgId = "clsypbcrw0001zqwy1arndx1t";
        sphinxConfig.projectName = "Liquidity_Pools";
        sphinxConfig.threshold = 1;
    }

    function run() public sphinx {

        address admin = vm.envAddress("ADMIN");

        AxelarForwarder router = new AxelarForwarder(address(vm.envAddress("AXELAR_GATEWAY")));

        router.rely(admin);
    }
}
