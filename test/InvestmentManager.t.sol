pragma solidity 0.8.21;
// SPDX-License-Identifier: AGPL-3.0-only
pragma abicoder v2;

import "./TestSetup.t.sol";

interface LiquidityPoolLike {
    function latestPrice() external view returns (uint128);
    function lastPriceUpdate() external view returns (uint256);
}

contract InvestmentManagerTest is TestSetup {
    function testUpdatingTokenPriceWorks(
        uint64 poolId,
        uint8 decimals,
        uint128 currencyId,
        address currency,
        string memory tokenName,
        string memory tokenSymbol,
        bytes16 trancheId,
        uint128 price
    ) public {
        vm.assume(decimals <= 18);
        vm.assume(poolId > 0);
        vm.assume(trancheId > 0);
        vm.assume(currencyId > 0);
        homePools.addPool(poolId); // add pool
        homePools.addTranche(poolId, trancheId, tokenName, tokenSymbol, decimals); // add tranche
        homePools.addCurrency(currencyId, address(erc20)); // add currency
        homePools.allowPoolCurrency(poolId, currencyId);

        address tranche_ = evmPoolManager.deployTranche(poolId, trancheId);
        LiquidityPoolLike lPool =
            LiquidityPoolLike(evmPoolManager.deployLiquidityPool(poolId, trancheId, address(erc20)));

        homePools.updateTrancheTokenPrice(poolId, trancheId, currencyId, price);
        assertEq(lPool.latestPrice(), price);
        assertEq(lPool.lastPriceUpdate(), block.timestamp);
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

        vm.expectRevert(bytes("InvestmentManager/not-the-gateway"));
        evmInvestmentManager.updateTrancheTokenPrice(poolId, trancheId, currency, price);
    }

    function testUpdatingTokenPriceForNonExistentTrancheFails(
        uint64 poolId,
        bytes16 trancheId,
        uint128 currencyId,
        uint128 price
    ) public {
        homePools.addPool(poolId);

        vm.expectRevert(bytes("InvestmentManager/tranche-does-not-exist"));
        homePools.updateTrancheTokenPrice(poolId, trancheId, currencyId, price);
    }
}
