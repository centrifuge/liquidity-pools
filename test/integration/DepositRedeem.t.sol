// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import "./../BaseTest.sol";

contract DepositRedeem is BaseTest {
    function testPartialDepositAndRedeemExecutions(uint64 poolId, bytes16 trancheId, uint128 currencyId) public {
        vm.assume(currencyId > 0);

        uint8 TRANCHE_TOKEN_DECIMALS = 18; // Like DAI
        uint8 INVESTMENT_CURRENCY_DECIMALS = 6; // 6, like USDC

        ERC20 currency = _newErc20("Currency", "CR", INVESTMENT_CURRENCY_DECIMALS);
        address vault_ = deployVault(
            poolId, TRANCHE_TOKEN_DECIMALS, defaultRestrictionSet, "", "", trancheId, currencyId, address(currency)
        );
        ERC7540Vault vault = ERC7540Vault(vault_);

        centrifugeChain.updateTrancheTokenPrice(
            poolId, trancheId, currencyId, 1000000000000000000, uint64(block.timestamp)
        );

        partialDeposit(poolId, trancheId, vault, currency);

        partialRedeem(poolId, trancheId, vault, currency);
    }

    // Helpers

    function partialDeposit(uint64 poolId, bytes16 trancheId, ERC7540Vault vault, ERC20 currency) public {
        TrancheTokenLike trancheToken = TrancheTokenLike(address(vault.share()));

        uint256 investmentAmount = 100000000; // 100 * 10**6
        centrifugeChain.updateMember(poolId, trancheId, self, type(uint64).max);
        currency.approve(address(vault), investmentAmount);
        currency.mint(self, investmentAmount);
        vault.requestDeposit(investmentAmount, self, self, "");

        // first trigger executed collectInvest of the first 50% at a price of 1.4
        uint128 _currencyId = poolManager.currencyAddressToId(address(currency)); // retrieve currencyId
        uint128 currencyPayout = 50000000; // 50 * 10**6
        uint128 firstTrancheTokenPayout = 35714285714285714285; // 50 * 10**18 / 1.4, rounded down
        centrifugeChain.isExecutedCollectInvest(
            poolId,
            trancheId,
            bytes32(bytes20(self)),
            _currencyId,
            currencyPayout,
            firstTrancheTokenPayout,
            currencyPayout
        );

        (, uint256 depositPrice,,,,,,,,,) = investmentManager.investments(address(vault), self);
        assertEq(depositPrice, 1400000000000000000);

        // second trigger executed collectInvest of the second 50% at a price of 1.2
        uint128 secondTrancheTokenPayout = 41666666666666666666; // 50 * 10**18 / 1.2, rounded down
        centrifugeChain.isExecutedCollectInvest(
            poolId, trancheId, bytes32(bytes20(self)), _currencyId, currencyPayout, secondTrancheTokenPayout, 0
        );

        (, depositPrice,,,,,,,,,) = investmentManager.investments(address(vault), self);
        assertEq(depositPrice, 1292307679384615384);

        // assert deposit & mint values adjusted
        assertApproxEqAbs(vault.maxDeposit(self), currencyPayout * 2, 2);
        assertEq(vault.maxMint(self), firstTrancheTokenPayout + secondTrancheTokenPayout);

        // collect the tranche tokens
        vault.mint(firstTrancheTokenPayout + secondTrancheTokenPayout, self);
        assertEq(trancheToken.balanceOf(self), firstTrancheTokenPayout + secondTrancheTokenPayout);
    }

    function partialRedeem(uint64 poolId, bytes16 trancheId, ERC7540Vault vault, ERC20 currency) public {
        TrancheTokenLike trancheToken = TrancheTokenLike(address(vault.share()));

        uint128 currencyId = poolManager.currencyAddressToId(address(currency));
        uint256 totalTrancheTokens = trancheToken.balanceOf(self);
        uint256 redeemAmount = 50000000000000000000;
        assertTrue(redeemAmount <= totalTrancheTokens);
        vault.requestRedeem(redeemAmount, self, self, "");

        // first trigger executed collectRedeem of the first 25 trancheTokens at a price of 1.1
        uint128 firstTrancheTokenRedeem = 25000000000000000000;
        uint128 secondTrancheTokenRedeem = 25000000000000000000;
        assertEq(firstTrancheTokenRedeem + secondTrancheTokenRedeem, redeemAmount);
        uint128 firstCurrencyPayout = 27500000; // (25000000000000000000/10**18) * 10**6 * 1.1
        centrifugeChain.isExecutedCollectRedeem(
            poolId, trancheId, bytes32(bytes20(self)), currencyId, firstCurrencyPayout, firstTrancheTokenRedeem
        );

        assertEq(vault.maxRedeem(self), firstTrancheTokenRedeem);

        (,,, uint256 redeemPrice,,,,,,,) = investmentManager.investments(address(vault), self);
        assertEq(redeemPrice, 1100000000000000000);

        // second trigger executed collectRedeem of the second 25 trancheTokens at a price of 1.3
        uint128 secondCurrencyPayout = 32500000; // (25000000000000000000/10**18) * 10**6 * 1.3
        centrifugeChain.isExecutedCollectRedeem(
            poolId, trancheId, bytes32(bytes20(self)), currencyId, secondCurrencyPayout, secondTrancheTokenRedeem
        );

        (,,, redeemPrice,,,,,,,) = investmentManager.investments(address(vault), self);
        assertEq(redeemPrice, 1200000000000000000);

        assertApproxEqAbs(vault.maxWithdraw(self), firstCurrencyPayout + secondCurrencyPayout, 2);
        assertEq(vault.maxRedeem(self), redeemAmount);

        // collect the currency
        vault.redeem(redeemAmount, self, self);
        assertEq(trancheToken.balanceOf(self), totalTrancheTokens - redeemAmount);
        assertEq(currency.balanceOf(self), firstCurrencyPayout + secondCurrencyPayout);
    }
}
