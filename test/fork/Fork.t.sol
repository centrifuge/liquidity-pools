// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import "forge-std/Test.sol";
import {Addresses} from "deployments/ETH_MAINNET.sol";
import {Root} from "src/Root.sol";
import {InvestmentManager} from "src/InvestmentManager.sol";
import {PoolManager} from "src/PoolManager.sol";
import {Escrow} from "src/Escrow.sol";
import {UserEscrow} from "src/UserEscrow.sol";
import {TrancheToken} from "src/token/Tranche.sol";
import {Gateway} from "src/gateway/Gateway.sol";
import {AxelarRouter} from "src/gateway/routers/axelar/Router.sol";
import {TrancheTokenFactory, LiquidityPoolFactory, RestrictionManagerFactory} from "src/util/Factory.sol";
import {DelayedAdmin} from "src/admins/DelayedAdmin.sol";
import {PauseAdmin} from "src/admins/PauseAdmin.sol";

contract ForkTest is Test, Addresses {
    uint256 mainnetFork;

    function setUp() public virtual {
        if (vm.envOr("FORK_TESTS", false)) {
            mainnetFork = vm.createFork(vm.rpcUrl("ethereum-mainnet")); // setup ETH mainnet fork
            vm.selectFork(mainnetFork);
        }
    }

    function testContractsWiredCorrectly() public {
        if (vm.envOr("FORK_TESTS", false)) {
            // investmentManager
            assertEq(address(InvestmentManager(investmentManager).escrow()), escrow);
            assertEq(address(InvestmentManager(investmentManager).userEscrow()), userEscrow);
            assertEq(address(InvestmentManager(investmentManager).gateway()), gateway);
            assertEq(address(InvestmentManager(investmentManager).poolManager()), poolManager);
            assertEq(address(Gateway(gateway).investmentManager()), investmentManager);
            assertEq(address(PoolManager(poolManager).investmentManager()), investmentManager);
            assertEq(InvestmentManager(investmentManager).wards(poolManager), 1);
            assertEq(Escrow(escrow).wards(investmentManager), 1);
            assertEq(UserEscrow(userEscrow).wards(investmentManager), 1);
            assertEq(InvestmentManager(investmentManager).wards(root), 1);
            assertEq(InvestmentManager(investmentManager).wards(deployer), 0); // deployer has no permissions

            // PoolManager
            assertEq(address(PoolManager(poolManager).gateway()), gateway);
            assertEq(address(PoolManager(poolManager).escrow()), escrow);
            assertEq(address(PoolManager(poolManager).investmentManager()), investmentManager);
            assertEq(address(PoolManager(poolManager).trancheTokenFactory()), trancheTokenFactory);
            assertEq(address(PoolManager(poolManager).liquidityPoolFactory()), liquidityPoolFactory);
            assertEq(address(PoolManager(poolManager).restrictionManagerFactory()), restrictionManagerFactory);
            assertEq(address(Gateway(gateway).poolManager()), poolManager);
            assertEq(address(InvestmentManager(investmentManager).poolManager()), poolManager);
            assertEq(InvestmentManager(investmentManager).wards(poolManager), 1);
            assertEq(Escrow(escrow).wards(poolManager), 1);
            assertEq(InvestmentManager(investmentManager).wards(poolManager), 1);
            assertEq(PoolManager(poolManager).wards(root), 1);
            assertEq(PoolManager(poolManager).wards(deployer), 0); // deployer has no permissions

            // Gateway
            assertEq(address(Gateway(gateway).investmentManager()), investmentManager);
            assertEq(address(Gateway(gateway).poolManager()), poolManager);
            assertEq(address(Gateway(gateway).root()), root);
            assertEq(address(InvestmentManager(investmentManager).gateway()), gateway);
            assertEq(address(PoolManager(poolManager).gateway()), gateway);
            assertEq(address(Gateway(gateway).outgoingRouter()), router);
            assertTrue(Gateway(gateway).incomingRouters(router));
            assertEq(Gateway(gateway).wards(root), 1);
            assertEq(Root(root).wards(gateway), 1);
            assertEq(Gateway(gateway).wards(deployer), 0); // deployer has no permissions

            // Escrow
            assertEq(Escrow(escrow).wards(root), 1);
            assertEq(Escrow(escrow).wards(deployer), 0); // deployer has no permissions

            // UserEscrow
            assertEq(UserEscrow(userEscrow).wards(root), 1);
            assertEq(UserEscrow(userEscrow).wards(deployer), 0); // deployer has no permissions

            // router
            assertEq(AxelarRouter(router).wards(root), 1);
            assertEq(AxelarRouter(router).wards(deployer), 0); // deployer has no permissions

            // trancheTokenFactory
            assertEq(address(PoolManager(poolManager).trancheTokenFactory()), trancheTokenFactory);
            assertEq(TrancheTokenFactory(trancheTokenFactory).wards(root), 1);
            assertEq(TrancheTokenFactory(trancheTokenFactory).wards(deployer), 0); // deployer has no permissions

            // liquidityPoolFactory
            assertEq(address(PoolManager(poolManager).liquidityPoolFactory()), liquidityPoolFactory);
            assertEq(LiquidityPoolFactory(liquidityPoolFactory).root(), root);
            assertEq(LiquidityPoolFactory(liquidityPoolFactory).wards(root), 1);
            assertEq(LiquidityPoolFactory(liquidityPoolFactory).wards(poolManager), 1);
            assertEq(LiquidityPoolFactory(liquidityPoolFactory).wards(deployer), 0); // deployer has no permissions

            // restrictionMangerFactory
            assertEq(address(PoolManager(poolManager).restrictionManagerFactory()), restrictionManagerFactory);
            assertEq(RestrictionManagerFactory(restrictionManagerFactory).wards(root), 1);
            assertEq(RestrictionManagerFactory(restrictionManagerFactory).wards(deployer), 0); // deployer has no
                // permissions

            // delayedAdmin
            assertEq(address(DelayedAdmin(delayedAdmin).root()), root);
            assertEq(DelayedAdmin(delayedAdmin).wards(admin), 1);
            assertEq(Root(root).wards(delayedAdmin), 1);
            assertEq(DelayedAdmin(delayedAdmin).wards(root), 0);
            assertEq(DelayedAdmin(delayedAdmin).wards(deployer), 0); // deployer has no permissions

            // pauseAdmin
            assertEq(address(PauseAdmin(pauseAdmin).root()), root);
            assertEq(PauseAdmin(pauseAdmin).wards(delayedAdmin), 1);
            // assertEq(PauseAdmin(pauseAdmin).wards(admin), 0); // todo: add once spell executed
            assertEq(Root(root).wards(pauseAdmin), 1);
            assertEq(PauseAdmin(pauseAdmin).wards(root), 0);
            assertEq(PauseAdmin(pauseAdmin).wards(deployer), 0); // deployer has no permissions
        }
    }
}
