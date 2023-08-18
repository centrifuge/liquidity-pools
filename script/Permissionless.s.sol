// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.18;

import {PermissionlessRouter} from "test/mock/PermissionlessRouter.sol";
import {Deployer} from "./Deployer.sol";
import "forge-std/Script.sol";

// Script to deploy Liquidity Pools with a permissionless router for testing.
contract PermissionlessScript is Script {
    // address(0)[0:20] + keccak("Centrifuge")[21:32]
    bytes32 SALT = 0x000000000000000000000000000000000000000075eb27011b69f002dc094d05;

    function setUp() public {}

    function run() public {
        vm.startBroadcast();

        Deployer deployer = new Deployer();
        address investmentManager = deployer.deployInvestmentManager();

        PermissionlessRouter router = new PermissionlessRouter();

        deployer.wire(router);

        vm.stopBroadcast();
    }
}
