// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import {MigratedLiquidityPool, LiquidityPool} from "./migrationContracts/MigratedLiquidityPool.sol";
import {MigratedPoolManager, PoolManager} from "./migrationContracts/MigratedPoolManager.sol";
import {LiquidityPoolFactory, TrancheTokenFactory} from "src/util/Factory.sol";
import {InvestRedeemFlow} from "./InvestRedeemFlow.t.sol";

interface TrancheTokenLike {
    function rely(address usr) external;
    function deny(address usr) external;
    function restrictionManager() external view returns (address);
    function addTrustedForwarder(address forwarder) external;
    function removeTrustedForwarder(address forwarder) external;
    function trustedForwarders(address) external view returns (bool);
    function wards(address) external view returns (uint256);
    function allowance(address, address) external view returns (uint256);
}

interface AuthLike {
    function rely(address) external;
    function deny(address) external;
}

contract MigrationsTest is InvestRedeemFlow {
    function setUp() public override {
        super.setUp();
    }

    function testLiquidityPoolMigration() public {
        centrifugeChain.incomingScheduleUpgrade(address(this));
        vm.warp(block.timestamp + 3 days);
        root.executeScheduledRely(address(this));

        LiquidityPool oldLiquidityPool = LiquidityPool(lPool_);
        uint64 poolId = oldLiquidityPool.poolId();
        bytes16 trancheId = oldLiquidityPool.trancheId();
        address currency = address(oldLiquidityPool.asset());

        LiquidityPoolFactory newLiquidityPoolFactory = new LiquidityPoolFactory(address(root));
        newLiquidityPoolFactory.rely(address(root));

        // rewire factory contracts
        newLiquidityPoolFactory.rely(address(poolManager));
        root.relyContract(address(poolManager), address(this));
        poolManager.file("liquidityPoolFactory", address(newLiquidityPoolFactory));

        // Remove old liquidity pool
        poolManager.removeLiquidityPool(poolId, trancheId, currency);
        assertEq(poolManager.getLiquidityPool(poolId, trancheId, currency), address(0));

        // Deploy new liquidity pool
        address newLiquidityPool = poolManager.deployLiquidityPool(poolId, trancheId, currency);
        assertEq(poolManager.getLiquidityPool(poolId, trancheId, currency), newLiquidityPool);

        root.denyContract(address(poolManager), address(this));
        root.denyContract(address(newLiquidityPoolFactory), address(this));

        // verify permissions
        verifyLiquidityPoolPermissions(LiquidityPool(lPool_), LiquidityPool(newLiquidityPool));

        lPool_ = address(newLiquidityPool);
        verifyInvestAndRedeemFlow(poolId, trancheId, lPool_);
    }

    // --- Permissions & Dependencies Checks ---

    function verifyLiquidityPoolPermissions(LiquidityPool oldLiquidityPool, LiquidityPool newLiquidityPool) public {
        // verify permissions
        assertTrue(address(oldLiquidityPool) != address(newLiquidityPool));
        address token = poolManager.getTrancheToken(poolId, trancheId);
        assertEq(TrancheTokenLike(token).wards(address(oldLiquidityPool)), 0);
        assertEq(TrancheTokenLike(token).wards(address(newLiquidityPool)), 1);
        assertEq(TrancheTokenLike(token).trustedForwarders(address(oldLiquidityPool)), false);
        assertEq(TrancheTokenLike(token).trustedForwarders(address(newLiquidityPool)), true);
        assertEq(poolManager.getLiquidityPool(poolId, trancheId, address(erc20)), address(newLiquidityPool));
        assertEq(investmentManager.wards(address(newLiquidityPool)), 1);
        assertEq(investmentManager.wards(address(oldLiquidityPool)), 0);
        assertEq(newLiquidityPool.wards(address(root)), 1);
        assertEq(newLiquidityPool.wards(address(investmentManager)), 1);
        assertEq(TrancheTokenLike(token).allowance(address(escrow), address(oldLiquidityPool)), 0);
        assertEq(TrancheTokenLike(token).allowance(address(escrow), address(newLiquidityPool)), type(uint256).max);

        // verify dependancies
        assertEq(oldLiquidityPool.poolId(), newLiquidityPool.poolId());
        assertEq(oldLiquidityPool.trancheId(), newLiquidityPool.trancheId());
        assertEq(address(oldLiquidityPool.asset()), address(newLiquidityPool.asset()));
        assertEq(address(oldLiquidityPool.share()), address(newLiquidityPool.share()));
        assertEq(address(newLiquidityPool.share()), token);
        assertEq(address(oldLiquidityPool.manager()), address(newLiquidityPool.manager()));
    }
}
