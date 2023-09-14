// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import {PermissionlessRouter} from "test/mock/PermissionlessRouter.sol";
import {InvestmentManager} from "src/InvestmentManager.sol";
import {Deployer, RouterLike} from "./Deployer.sol";

// Script to deploy Liquidity Pools with a permissionless router for testing.
contract PermissionlessScript is Deployer {
    function setUp() public {}

    function run() public {
        vm.startBroadcast();

        admin = msg.sender;

        // Deploy contracts
        deployInvestmentManager();
        PermissionlessRouter router = new PermissionlessRouter();
        wire(address(router));
        RouterLike(address(router)).file("gateway", address(gateway));

        // Set up test data
        if (vm.envOr("SETUP_TEST_DATA", false)) {
            root.relyContract(address(poolManager), address(this));
            poolManager.file("gateway", admin);
            root.relyContract(address(investmentManager), address(this));
            investmentManager.file("gateway", admin);
            poolManager.addCurrency(1, 0xd35CCeEAD182dcee0F148EbaC9447DA2c4D449c4);
            poolManager.addPool(1171854325);
            poolManager.addTranche(1171854325, 0x102f4ef817340a8839a515d2c73a7c1d, "Some Token", "ST", 6);
            poolManager.deployTranche(1171854325, 0x102f4ef817340a8839a515d2c73a7c1d);
            poolManager.allowPoolCurrency(1171854325, 1);
            poolManager.deployLiquidityPool(
                1171854325, 0x102f4ef817340a8839a515d2c73a7c1d, 0xd35CCeEAD182dcee0F148EbaC9447DA2c4D449c4
            );
            poolManager.updateMember(1171854325, 0x102f4ef817340a8839a515d2c73a7c1d, admin, type(uint64).max);
        }

        giveAdminAccess();

        vm.stopBroadcast();
    }
}
