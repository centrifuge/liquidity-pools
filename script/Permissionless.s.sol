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

        address admin = msg.sender;

        // Deploy contracts
        Deployer deployer = new Deployer(admin);
        investmentManager = deployer.deployInvestmentManager();
        PermissionlessRouter router = new PermissionlessRouter();
        deployer.wire(address(router));

        // Set up test data
        InvestmentManager mgr = InvestmentManager(investmentManager);
        mgr.addPool(1171854325);
        mgr.addTranche(1171854325, 0x102f4ef817340a8839a515d2c73a7c1d, "Some Token", "ST", 6, 1e27);
        mgr.addCurrency(1, 0xd35cceead182dcee0f148ebac9447da2c4d449c4);
        mgr.allowPoolCurrency(1171854325, 1);
        mgr.deployLiquidityPool(1171854325, 0x102f4ef817340a8839a515d2c73a7c1d, 0xd35cceead182dcee0f148ebac9447da2c4d449c4);
        mgr.updateMember(1171854325, 0x102f4ef817340a8839a515d2c73a7c1d, admin, type(uint64).max);

        deployer.giveAdminAccess();
        deployer.removeDeployerAccess();

        vm.stopBroadcast();
    }
}
