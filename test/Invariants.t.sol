// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import {TestSetup} from "test/TestSetup.t.sol";
import {InvariantPoolManager} from "test/accounts/PoolManager.sol";
import "forge-std/Test.sol";

interface LiquidityPoolLike {
    function poolId() external returns (uint64);
    function trancheId() external returns (bytes16);
}

contract ConnectorInvariants is TestSetup {
    InvariantPoolManager invariantPoolManager;

    address[] private targetContracts_;

    function setUp() public override {
        super.setUp();

        // Performs random pool and tranches creations
        invariantPoolManager = new InvariantPoolManager(homePools);
        targetContracts_.push(address(poolManager));
    }

    function targetContracts() public returns (address[] memory) {
        return targetContracts_;
    }

    // Invariant 1: For every liquidity pool that exists, the equivalent tranche and pool exists
    function invariantLiquidityPoolRequiresTrancheAndPool() external {
        for (uint256 i = 0; i < invariantPoolManager.allLiquidityPoolsLength(); i++) {
            address liquidityPool = invariantPoolManager.allLiquidityPools(i);
            uint64 poolId = LiquidityPoolLike(liquidityPool).poolId();
            bytes16 trancheId = LiquidityPoolLike(liquidityPool).trancheId();
            (,, uint256 createdAt) = poolManager.pools(poolId);
            assertTrue(createdAt > 0);
            address token = poolManager.getTrancheToken(poolId, trancheId);
            assertTrue(token != address(0));
            assertTrue(invariantPoolManager.trancheIdToPoolId(trancheId) == poolId);
        }
    }
}
