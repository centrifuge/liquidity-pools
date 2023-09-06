// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import {TestSetup} from "test/TestSetup.t.sol";
import {InvariantPoolManager} from "test/accounts/PoolManager.sol";
import {InvestorManager} from "test/accounts/InvestorManager.sol";
import "forge-std/Test.sol";

interface LiquidityPoolLike {
    function poolId() external returns (uint64);
    function trancheId() external returns (bytes16);
    function totalSupply() external returns (uint256);
}

contract PoolInvariants is TestSetup {
    InvariantPoolManager invariantPoolManager;
    InvestorManager investor;

    address[] private targetContracts_;

    function setUp() public override {
        super.setUp();

        // Performs random pool, tranche, and liquidityPool creations
        invariantPoolManager = new InvariantPoolManager(homePools);
        targetContracts_.push(address(poolManager));

        // Performs random transfers in and out
        investor = new InvestorManager();
        targetContracts_.push(address(investor));
    }

    function targetContracts() public returns (address[] memory) {
        return targetContracts_;
    }

    // Invariant 1: For every liquidity pool that exists, the equivalent tranche and pool exists
    function invariant_LiquidityPoolRequiresTrancheAndPool() external {
        for (uint256 i = 0; i < invariantPoolManager.allLiquidityPoolsLength(); i++) {
            address liquidityPool = invariantPoolManager.allLiquidityPools(i);
            uint64 poolId = LiquidityPoolLike(liquidityPool).poolId();
            bytes16 trancheId = LiquidityPoolLike(liquidityPool).trancheId();
            (, uint256 createdAt) = poolManager.pools(poolId);
            assertTrue(createdAt > 0);
            address token = poolManager.getTrancheToken(poolId, trancheId);
            assertTrue(token != address(0));
            assertTrue(invariantPoolManager.trancheIdToPoolId(trancheId) == poolId);
        }
    }

    function invariant_tokenSolvency() external {
        for (uint256 i = 0; i < invariantPoolManager.allLiquidityPoolsLength(); i++) {
            address liquidityPool = invariantPoolManager.allLiquidityPools(i);
            assertEq(LiquidityPoolLike(liquidityPool).totalSupply(), investor.totalTransferredIn() - investor.totalTransferredOut());
        }
    }
}
