// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import {TestSetup} from "test/TestSetup.t.sol";
import {InvariantPoolManager} from "test/accounts/PoolManager.sol";
import {InvestorManager} from "test/accounts/InvestorManager.sol";
import "forge-std/Test.sol";

interface LiquidityPoolLike {
    function poolId() external returns (uint64);
    function trancheId() external returns (bytes16);
}

interface ERC20Like {
    function totalSupply() external returns (uint256);
    function balanceOf(address account) external view returns (uint256);
}

contract PoolInvariants is TestSetup {
    InvariantPoolManager invariantPoolManager;
    InvestorManager investor;

    address[] private targetContracts_;

    function setUp() public override {
        super.setUp();

        // Performs random pool, tranche, and liquidityPool creations
        invariantPoolManager = new InvariantPoolManager(homePools);
        targetContract(address(poolManager));

        // Performs random transfers in and out
        investor = new InvestorManager();
        targetContract(address(investor));
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

    // Invariant 2: The tranche token supply should equal the sum of all transfers in minus the sum of all the transfers out
    function invariant_tokenSolvency() external {
        assertEq(
            ERC20Like(investor.fixedToken()).totalSupply(),
            investor.totalTransferredIn() - investor.totalTransferredOut()
        );
    }

    // Invariant 3: An investor should not be able to transfer out more tranche tokens than were transferred in
    function invariant_investorSolvency() external {
        assertTrue(investor.totalTransferredIn() >= investor.totalTransferredOut());
        for (uint256 i = 0; i < investor.allInvestorsLength(); i++) {
            address investorAddress = investor.allInvestors(i);
            assertTrue(
                investor.investorTransferredIn(investorAddress) >= investor.investorTransferredOut(investorAddress)
            );
        }
    }

    // Invariant 4: The total supply of tranche tokens should equal the sum of all the investors balances
    function invariant_totalSupply() external {
        uint256 totalSupply = ERC20Like(investor.fixedToken()).totalSupply();
        uint256 totalBalance = 0;
        for (uint256 i = 0; i < investor.allInvestorsLength(); i++) {
            totalBalance += ERC20Like(investor.fixedToken()).balanceOf(investor.allInvestors(i));
        }
        assertEq(totalSupply, totalBalance);
    }
}
