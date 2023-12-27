// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import {TestSetup} from "test/TestSetup.t.sol";
import {PoolManagerHandler} from "test/invariant/handlers/PoolManager.sol";
import {TrancheTokenHolderHandler} from "test/invariant/handlers/TrancheTokenHolder.sol";
import "forge-std/Test.sol";

interface LiquidityPoolLike {
    function poolId() external returns (uint64);
    function trancheId() external returns (bytes16);
}

interface ERC20Like {
    function totalSupply() external returns (uint256);
    function balanceOf(address account) external view returns (uint256);
}

contract PoolManagerInvariants is TestSetup {
    PoolManagerHandler poolManagerHandler;
    TrancheTokenHolderHandler trancheTokenHolder;

    function setUp() public override {
        super.setUp();

        deployLiquidityPool(1, erc20.decimals(), defaultRestrictionSet, "", "", "1", 1, address(erc20));

        // Performs random pool, tranche, and liquidityPool creations
        poolManagerHandler = new PoolManagerHandler(address(centrifugeChain), address(poolManager));
        targetContract(address(poolManagerHandler));

        // Performs random transfers in and out
        trancheTokenHolder = new TrancheTokenHolderHandler(1, "1", 1, address(centrifugeChain), address(poolManager));
        centrifugeChain.updateMember(1, "1", address(trancheTokenHolder), type(uint64).max);
        targetContract(address(trancheTokenHolder));
    }

    // Invariant 1: For every liquidity pool that exists, the equivalent tranche and pool exists
    function invariant_LiquidityPoolRequiresTrancheAndPool() external {
        for (uint256 i = 0; i < poolManagerHandler.allLiquidityPoolsLength(); i++) {
            address liquidityPool = poolManagerHandler.allLiquidityPools(i);
            uint64 poolId = LiquidityPoolLike(liquidityPool).poolId();
            bytes16 trancheId = LiquidityPoolLike(liquidityPool).trancheId();
            (uint256 createdAt) = poolManager.pools(poolId);
            assertTrue(createdAt > 0);
            address token = poolManager.getTrancheToken(poolId, trancheId);
            assertTrue(token != address(0));
            assertTrue(poolManagerHandler.trancheIdToPoolId(trancheId) == poolId);
        }
    }

    // Invariant 2: The tranche token supply should equal the sum of all transfers in minus the sum of all the transfers
    // out
    function invariant_tokenSolvency() external {
        assertEq(
            trancheTokenHolder.trancheToken().totalSupply(),
            trancheTokenHolder.totalTransferredIn() - trancheTokenHolder.totalTransferredOut()
        );
    }

    // Invariant 3: An investor should not be able to transfer out more tranche tokens than were transferred in
    function invariant_investorSolvency() external {
        assertTrue(trancheTokenHolder.totalTransferredIn() >= trancheTokenHolder.totalTransferredOut());
        for (uint256 i = 0; i < trancheTokenHolder.allInvestorsLength(); i++) {
            address investorAddress = trancheTokenHolder.allInvestors(i);
            assertTrue(
                trancheTokenHolder.investorTransferredIn(investorAddress)
                    >= trancheTokenHolder.investorTransferredOut(investorAddress)
            );
        }
    }

    // Invariant 4: The total supply of tranche tokens should equal the sum of all the investors balances
    function invariant_totalSupply() external {
        uint256 totalSupply = trancheTokenHolder.trancheToken().totalSupply();
        uint256 totalBalance = 0;
        for (uint256 i = 0; i < trancheTokenHolder.allInvestorsLength(); i++) {
            totalBalance += trancheTokenHolder.trancheToken().balanceOf(trancheTokenHolder.allInvestors(i));
        }
        assertEq(totalSupply, totalBalance);
    }
}
