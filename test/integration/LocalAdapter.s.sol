// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.26;

import {Deployer} from "../../script/Deployer.sol";
import {LocalAdapter} from "./LocalAdapter.sol";

// Script to deploy Liquidity Pools with an Axelar router.
contract LocalAdapterScript is Deployer {
    function setUp() public {}

    function run() public {
        vm.startBroadcast();

        // NOTE: 0x361c43cd5Fd700923Aae9dED678851a201839fc6 is the H160 of Keyring::Admin in the Centrifuge Chain
        // repository
        adminSafe = address(0x361c43cd5Fd700923Aae9dED678851a201839fc6);

        deploy(msg.sender);
        LocalAdapter router = new LocalAdapter();
        wire(address(router));

        router.file("gateway", address(gateway));
        router.file("sourceChain", "TestDomain");
        router.file("sourceAddress", "0x1111111111111111111111111111111111111111");

        removeDeployerAccess(address(router), msg.sender);

        vm.stopBroadcast();
    }
}
