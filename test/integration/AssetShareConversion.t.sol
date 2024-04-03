// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import "./../BaseTest.sol";

contract AssetShareConversionTest is BaseTest {
    function testAssetShareConversion(uint64 poolId, bytes16 trancheId, uint128 currencyId) public {
        vm.assume(currencyId > 0);

        uint8 INVESTMENT_CURRENCY_DECIMALS = 6; // 6, like USDC
        uint8 TRANCHE_TOKEN_DECIMALS = 18; // Like DAI

        ERC20 currency = _newErc20("Currency", "CR", INVESTMENT_CURRENCY_DECIMALS);
        address lPool_ = deployLiquidityPool(
            poolId, TRANCHE_TOKEN_DECIMALS, defaultRestrictionSet, "", "", trancheId, currencyId, address(currency)
        );
        LiquidityPool lPool = LiquidityPool(lPool_);
        TrancheTokenLike trancheToken = TrancheTokenLike(address(LiquidityPool(lPool_).share()));

        assertEq(lPool.priceLastUpdated(), 0);
        centrifugeChain.updateTrancheTokenPrice(poolId, trancheId, currencyId, 1000000, uint64(block.timestamp));
        assertEq(lPool.priceLastUpdated(), uint64(block.timestamp));

        // invest
        uint256 investmentAmount = 100000000; // 100 * 10**6
        centrifugeChain.updateMember(poolId, trancheId, self, type(uint64).max);
        currency.approve(lPool_, investmentAmount);
        currency.mint(self, investmentAmount);
        lPool.requestDeposit(investmentAmount, self, self, "");

        // trigger executed collectInvest at a price of 1.0
        uint128 _currencyId = poolManager.currencyAddressToId(address(currency)); // retrieve currencyId
        uint128 trancheTokenPayout = 100000000000000000000; // 100 * 10**18
        centrifugeChain.isExecutedCollectInvest(
            poolId, trancheId, bytes32(bytes20(self)), _currencyId, uint128(investmentAmount), trancheTokenPayout, 0
        );
        lPool.mint(trancheTokenPayout, self);
        centrifugeChain.updateTrancheTokenPrice(
            poolId, trancheId, currencyId, 1000000000000000000, uint64(block.timestamp)
        );

        // assert share/asset conversion
        assertEq(trancheToken.totalSupply(), 100000000000000000000);
        assertEq(lPool.totalAssets(), 100000000);
        assertEq(lPool.convertToShares(100000000), 100000000000000000000); // tranche tokens have 12 more decimals than
            // assets
        assertEq(lPool.convertToAssets(lPool.convertToShares(100000000000000000000)), 100000000000000000000);

        // assert share/asset conversion after price update
        centrifugeChain.updateTrancheTokenPrice(
            poolId, trancheId, currencyId, 1200000000000000000, uint64(block.timestamp)
        );

        assertEq(lPool.totalAssets(), 120000000);
        assertEq(lPool.convertToShares(120000000), 100000000000000000000); // tranche tokens have 12 more decimals than
            // assets
        assertEq(lPool.convertToAssets(lPool.convertToShares(120000000000000000000)), 120000000000000000000);
    }

    function testAssetShareConversionWithInverseDecimals(uint64 poolId, bytes16 trancheId, uint128 currencyId) public {
        vm.assume(currencyId > 0);

        uint8 INVESTMENT_CURRENCY_DECIMALS = 18; // 18, like DAI
        uint8 TRANCHE_TOKEN_DECIMALS = 6; // Like USDC

        ERC20 currency = _newErc20("Currency", "CR", INVESTMENT_CURRENCY_DECIMALS);
        address lPool_ = deployLiquidityPool(
            poolId, TRANCHE_TOKEN_DECIMALS, defaultRestrictionSet, "", "", trancheId, currencyId, address(currency)
        );
        LiquidityPool lPool = LiquidityPool(lPool_);
        TrancheTokenLike trancheToken = TrancheTokenLike(address(LiquidityPool(lPool_).share()));
        centrifugeChain.updateTrancheTokenPrice(poolId, trancheId, currencyId, 1000000, uint64(block.timestamp));

        // invest
        uint256 investmentAmount = 100000000000000000000; // 100 * 10**18
        centrifugeChain.updateMember(poolId, trancheId, self, type(uint64).max);
        currency.approve(lPool_, investmentAmount);
        currency.mint(self, investmentAmount);
        lPool.requestDeposit(investmentAmount, self, self, "");

        // trigger executed collectInvest at a price of 1.0
        uint128 _currencyId = poolManager.currencyAddressToId(address(currency)); // retrieve currencyId
        uint128 trancheTokenPayout = 100000000; // 100 * 10**6
        centrifugeChain.isExecutedCollectInvest(
            poolId, trancheId, bytes32(bytes20(self)), _currencyId, uint128(investmentAmount), trancheTokenPayout, 0
        );
        lPool.mint(trancheTokenPayout, self);
        centrifugeChain.updateTrancheTokenPrice(
            poolId, trancheId, currencyId, 1000000000000000000, uint64(block.timestamp)
        );

        // assert share/asset conversion
        assertEq(trancheToken.totalSupply(), 100000000);
        assertEq(lPool.totalAssets(), 100000000000000000000);
        assertEq(lPool.convertToShares(100000000000000000000), 100000000); // tranche tokens have 12 less decimals than
            // assets
        assertEq(lPool.convertToAssets(lPool.convertToShares(100000000000000000000)), 100000000000000000000);

        // assert share/asset conversion after price update
        centrifugeChain.updateTrancheTokenPrice(
            poolId, trancheId, currencyId, 1200000000000000000, uint64(block.timestamp)
        );

        assertEq(lPool.totalAssets(), 120000000000000000000);
        assertEq(lPool.convertToShares(120000000000000000000), 100000000); // tranche tokens have 12 less decimals than
            // assets
        assertEq(lPool.convertToAssets(lPool.convertToShares(120000000000000000000)), 120000000000000000000);
    }
}
