// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.26;

import {Deployer} from "../../script/Deployer.sol";
import {LocalAdapter} from "./LocalAdapter.sol";

// Script to deploy Liquidity Pools with an Axelar adapter.
contract LocalAdapterScript is Deployer {
    function setUp() public {}

    function run() public {
        vm.startBroadcast();

        // NOTE: 0x361c43cd5Fd700923Aae9dED678851a201839fc6 is the H160 of Keyring::Admin in the Centrifuge Chain
        // repository
        address _admin = address(0x361c43cd5Fd700923Aae9dED678851a201839fc6);

        LocalAdapter adapter = new LocalAdapter();
        address[] memory _adapters = new address[](1);
        _adapters[0] = address(adapter);
        deploy(msg.sender, _admin, _adapters);

        adapter.file("gateway", address(gateway));
        adapter.file("sourceChain", "TestDomain");
        adapter.file("sourceAddress", "0x1111111111111111111111111111111111111111");

        removeDeployerAccess();

        vm.stopBroadcast();
    }
}
