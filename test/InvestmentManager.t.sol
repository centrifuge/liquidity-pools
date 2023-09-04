pragma solidity 0.8.21;
// SPDX-License-Identifier: AGPL-3.0-only
pragma abicoder v2;

import "./TestSetup.t.sol";

contract InvestmentManagerTest is TestSetup {
    function testUpdatingTokenPriceWorks(
        uint64 poolId,
        uint8 decimals,
        uint128 currency,
        string memory tokenName,
        string memory tokenSymbol,
        bytes16 trancheId,
        uint128 price
    ) public {
        vm.assume(decimals <= 18);
        vm.assume(currency > 0);
        vm.assume(poolId > 0);
        vm.assume(trancheId > 0);
        homePools.addPool(poolId); // add pool
        homePools.addTranche(poolId, trancheId, tokenName, tokenSymbol, decimals); // add tranche

        address tranche_ = evmPoolManager.deployTranche(poolId, trancheId);

        homePools.updateTrancheTokenPrice(poolId, trancheId, currency, price);
        assertEq(LiquidityPool(tranche_).latestPrice(), price);
        assertEq(LiquidityPool(tranche_).lastPriceUpdate(), block.timestamp);
    }

    function testUpdatingTokenPriceAsNonRouterFails(
        uint64 poolId,
        uint8 decimals,
        uint128 currency,
        string memory tokenName,
        string memory tokenSymbol,
        bytes16 trancheId,
        uint128 price
    ) public {
        vm.assume(decimals <= 18);
        vm.assume(currency > 0);
        ERC20 erc20 = newErc20("X's Dollar", "USDX", 18);
        homePools.addPool(poolId); // add pool
        homePools.addTranche(poolId, trancheId, tokenName, tokenSymbol, decimals); // add tranche
        homePools.addCurrency(currency, address(erc20));
        homePools.allowPoolCurrency(poolId, currency);
        evmPoolManager.deployTranche(poolId, trancheId);
        evmPoolManager.deployLiquidityPool(poolId, trancheId, address(erc20));

        vm.expectRevert(bytes("PoolManager/not-the-gateway"));
        evmInvestmentManager.updateTrancheTokenPrice(poolId, trancheId, currency, price);
    }

    function testUpdatingTokenPriceForNonExistentTrancheFails(
        uint64 poolId,
        bytes16 trancheId,
        uint128 currencyId,
        uint128 price
    ) public {
        homePools.addPool(poolId);

        vm.expectRevert(bytes("PoolManager/unknown-token"));
        homePools.updateTrancheTokenPrice(poolId, trancheId, currencyId, price);
    }
}
