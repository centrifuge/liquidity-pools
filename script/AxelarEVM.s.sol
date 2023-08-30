// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.18;

import {AxelarEVMRouter} from "src/gateway/routers/axelar/EVMRouter.sol";
import {Deployer, RouterLike} from "./Deployer.sol";

// Script to deploy Liquidity Pools with an Axelar router.
contract AxelarEVMScript is Deployer {
    function setUp() public {}

    function run() public {
        vm.startBroadcast();

        admin = vm.envAddress("ADMIN");

        deployInvestmentManager();
        AxelarEVMRouter router = new AxelarEVMRouter(
                address(vm.envAddress("AXELAR_GATEWAY"))
        );
        wire(address(router));
        router.file("gateway", address(gateway));

        // Set up test data
        if (vm.envBool("SETUP_TEST_DATA")) {
            root.relyContract(address(tokenManager), address(this));
            tokenManager.file("gateway", admin);
            root.relyContract(address(investmentManager), address(this));
            investmentManager.file("gateway", admin);
            tokenManager.addCurrency(1, 0xd35CCeEAD182dcee0F148EbaC9447DA2c4D449c4);
            investmentManager.addPool(1171854325);
            investmentManager.addTranche(1171854325, 0x102f4ef817340a8839a515d2c73a7c1d, "Some Token", "ST", 6, 1e27);
            investmentManager.deployTranche(1171854325, 0x102f4ef817340a8839a515d2c73a7c1d);
            investmentManager.allowPoolCurrency(1171854325, 1);
            investmentManager.deployLiquidityPool(
                1171854325, 0x102f4ef817340a8839a515d2c73a7c1d, 0xd35CCeEAD182dcee0F148EbaC9447DA2c4D449c4
            );
            tokenManager.updateMember(1171854325, 0x102f4ef817340a8839a515d2c73a7c1d, admin, type(uint64).max);
            tokenManager.file("gateway", address(gateway));
            investmentManager.file("gateway", address(gateway));
        }

        giveAdminAccess();
        removeDeployerAccess(address(router));

        vm.stopBroadcast();
    }
}
