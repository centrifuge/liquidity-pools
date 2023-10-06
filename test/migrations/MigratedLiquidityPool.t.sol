// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import {MigratedLiquidityPool, LiquidityPool} from "./migrationContracts/MigratedLiquidityPool.sol";
import {InvestRedeemFlow} from "./InvestRedeemFlow.t.sol";

contract MigrationsTest is InvestRedeemFlow {
    function setUp() public override {
        super.setUp();
    }

    function testLiquidityPoolMigration() public {
        // Simulate intended upgrade flow
        centrifugeChain.incomingScheduleUpgrade(address(this));
        vm.warp(block.timestamp + 3 days);
        root.executeScheduledRely(address(this));

        // Deploy new LiquidityPool
        MigratedLiquidityPool newLiquidityPool = new MigratedLiquidityPool(
            poolId, trancheId, address(erc20), address(LiquidityPool(_lPool).share()), address(investmentManager)
        );

        // Rewire contracts
        newLiquidityPool.rely(address(root));
        newLiquidityPool.rely(address(investmentManager));
        root.relyContract(address(investmentManager), address(this));
        investmentManager.rely(address(newLiquidityPool));
        investmentManager.deny(_lPool);
        root.relyContract(address(escrow), address(this));
        escrow.approve(address(newLiquidityPool), address(investmentManager), type(uint256).max);
        escrow.approve(_lPool, address(investmentManager), 0);

        // clean up
        newLiquidityPool.deny(address(this));
        root.denyContract(address(investmentManager), address(this));
        root.denyContract(address(escrow), address(this));
        root.deny(address(this));

        // verify permissions
        verifyLiquidityPoolPermissions(LiquidityPool(_lPool), newLiquidityPool);

        // TODO: test that everything is working
        // _lPool = address(newLiquidityPool);
        // VerifyInvestAndRedeemFlow(poolId, trancheId, address(_lPool));
    }

    // --- Permissions & Dependencies Checks ---

    function verifyLiquidityPoolPermissions(LiquidityPool oldLiquidityPool, LiquidityPool newLiquidityPool) public {
        assertTrue(address(oldLiquidityPool) != address(newLiquidityPool));
        assertEq(oldLiquidityPool.poolId(), newLiquidityPool.poolId());
        assertEq(oldLiquidityPool.trancheId(), newLiquidityPool.trancheId());
        assertEq(address(oldLiquidityPool.asset()), address(newLiquidityPool.asset()));
        assertEq(address(oldLiquidityPool.share()), address(newLiquidityPool.share()));
        address token = poolManager.getTrancheToken(poolId, trancheId);
        assertEq(address(newLiquidityPool.share()), token);
        assertEq(address(oldLiquidityPool.investmentManager()), address(newLiquidityPool.investmentManager()));
        assertEq(newLiquidityPool.wards(address(root)), 1);
        assertEq(newLiquidityPool.wards(address(investmentManager)), 1);
        assertEq(investmentManager.wards(address(newLiquidityPool)), 1);
        assertEq(investmentManager.wards(address(oldLiquidityPool)), 0);
    }
}
