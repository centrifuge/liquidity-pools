// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import "./../BaseTest.sol";
import {CastLib} from "src/libraries/CastLib.sol";

contract RedeemTest is BaseTest {
    using CastLib for *;

    function testRedeem(uint256 amount) public {
        amount = uint128(bound(amount, 2, MAX_UINT128 / 2));

        address vault_ = deploySimpleVault();
        ERC7540Vault vault = ERC7540Vault(vault_);
        TrancheTokenLike trancheToken = TrancheTokenLike(address(vault.share()));

        deposit(vault_, self, amount); // deposit funds first
        centrifugeChain.updateTrancheTokenPrice(
            vault.poolId(), vault.trancheId(), defaultCurrencyId, defaultPrice, uint64(block.timestamp)
        );

        // will fail - zero deposit not allowed
        vm.expectRevert(bytes("InvestmentManager/zero-amount-not-allowed"));
        vault.requestRedeem(0, self, self, "");

        // will fail - investment currency not allowed
        centrifugeChain.disallowInvestmentCurrency(vault.poolId(), defaultCurrencyId);
        vm.expectRevert(bytes("InvestmentManager/asset-not-allowed"));
        vault.requestRedeem(amount, address(this), address(this), "");

        // success
        centrifugeChain.allowInvestmentCurrency(vault.poolId(), defaultCurrencyId);
        vault.requestRedeem(amount, address(this), address(this), "");
        assertEq(trancheToken.balanceOf(address(escrow)), amount);
        assertEq(vault.pendingRedeemRequest(0, self), amount);
        assertEq(vault.claimableRedeemRequest(0, self), 0);

        // fail: no tokens left
        vm.expectRevert(bytes("ERC7540Vault/insufficient-balance"));
        vault.requestRedeem(amount, address(this), address(this), "");

        // trigger executed collectRedeem
        uint128 _assetId = poolManager.assetToId(address(erc20)); // retrieve assetId
        uint128 currencyPayout = uint128((amount * 10 ** 18) / defaultPrice);
        centrifugeChain.isFulfilledRedeemRequest(
            vault.poolId(), vault.trancheId(), bytes32(bytes20(self)), _assetId, currencyPayout, uint128(amount)
        );

        // assert withdraw & redeem values adjusted
        assertEq(vault.maxWithdraw(self), currencyPayout); // max deposit
        assertEq(vault.maxRedeem(self), amount); // max deposit
        assertEq(vault.pendingRedeemRequest(0, self), 0);
        assertEq(vault.claimableRedeemRequest(0, self), amount);
        assertEq(trancheToken.balanceOf(address(escrow)), 0);
        assertEq(erc20.balanceOf(address(escrow)), currencyPayout);

        // can redeem to self
        vault.redeem(amount / 2, self, self); // redeem half the amount to own wallet

        // can also redeem to another user
        vault.redeem(amount / 2, investor, self); // redeem half the amount to investor wallet

        assertEq(trancheToken.balanceOf(self), 0);
        assertTrue(trancheToken.balanceOf(address(escrow)) <= 1);
        assertTrue(erc20.balanceOf(address(escrow)) <= 1);

        assertApproxEqAbs(erc20.balanceOf(self), (amount / 2), 1);
        assertApproxEqAbs(erc20.balanceOf(investor), (amount / 2), 1);
        assertTrue(vault.maxWithdraw(self) <= 1);
        assertTrue(vault.maxRedeem(self) <= 1);

        // withdrawing or redeeming more should revert
        vm.expectRevert(bytes("InvestmentManager/exceeds-redeem-limits"));
        vault.withdraw(2, investor, self);
        vm.expectRevert(bytes("InvestmentManager/exceeds-redeem-limits"));
        vault.redeem(2, investor, self);
    }

    function testWithdraw(uint256 amount) public {
        amount = uint128(bound(amount, 2, MAX_UINT128 / 2));

        address vault_ = deploySimpleVault();
        ERC7540Vault vault = ERC7540Vault(vault_);
        TrancheTokenLike trancheToken = TrancheTokenLike(address(vault.share()));

        deposit(vault_, self, amount); // deposit funds first
        centrifugeChain.updateTrancheTokenPrice(
            vault.poolId(), vault.trancheId(), defaultCurrencyId, defaultPrice, uint64(block.timestamp)
        );

        vault.requestRedeem(amount, address(this), address(this), "");
        assertEq(trancheToken.balanceOf(address(escrow)), amount);
        assertGt(vault.pendingRedeemRequest(0, self), 0);

        // trigger executed collectRedeem
        uint128 _assetId = poolManager.assetToId(address(erc20)); // retrieve assetId
        uint128 currencyPayout = uint128((amount * 10 ** 18) / defaultPrice);
        centrifugeChain.isFulfilledRedeemRequest(
            vault.poolId(), vault.trancheId(), bytes32(bytes20(self)), _assetId, currencyPayout, uint128(amount)
        );

        // assert withdraw & redeem values adjusted
        assertEq(vault.maxWithdraw(self), currencyPayout); // max deposit
        assertEq(vault.maxRedeem(self), amount); // max deposit
        assertEq(trancheToken.balanceOf(address(escrow)), 0);
        assertEq(erc20.balanceOf(address(escrow)), currencyPayout);

        // can redeem to self
        vault.withdraw(amount / 2, self, self); // redeem half the amount to own wallet

        // can also withdraw to another user
        vault.withdraw(amount / 2, investor, self); // redeem half the amount to investor wallet

        assertTrue(trancheToken.balanceOf(self) <= 1);
        assertTrue(erc20.balanceOf(address(escrow)) <= 1);
        assertApproxEqAbs(erc20.balanceOf(self), currencyPayout / 2, 1);
        assertApproxEqAbs(erc20.balanceOf(investor), currencyPayout / 2, 1);
        assertTrue(vault.maxRedeem(self) <= 1);
        assertTrue(vault.maxWithdraw(self) <= 1);
    }

    function testRedeemWithApproval(uint256 redemption1, uint256 redemption2) public {
        redemption1 = uint128(bound(redemption1, 2, MAX_UINT128 / 4));
        redemption2 = uint128(bound(redemption2, 2, MAX_UINT128 / 4));
        uint256 amount = redemption1 + redemption2;
        vm.assume(amountAssumption(amount));

        address vault_ = deploySimpleVault();
        ERC7540Vault vault = ERC7540Vault(vault_);
        TrancheTokenLike trancheToken = TrancheTokenLike(address(vault.share()));

        deposit(vault_, investor, amount); // deposit funds first // deposit funds first

        // investor can requestRedeem
        vm.prank(investor);
        vault.requestRedeem(amount, investor, investor, "");

        uint128 tokenAmount = uint128(trancheToken.balanceOf(address(escrow)));
        centrifugeChain.isFulfilledRedeemRequest(
            vault.poolId(),
            vault.trancheId(),
            bytes32(bytes20(investor)),
            defaultCurrencyId,
            uint128(amount),
            uint128(tokenAmount)
        );

        assertEq(vault.maxRedeem(investor), tokenAmount);
        assertEq(vault.maxWithdraw(investor), uint128(amount));

        // test for both scenarios redeem & withdraw

        // fail: self cannot redeem for investor
        vm.expectRevert(bytes("ERC7540Vault/not-the-owner"));
        vault.redeem(redemption1, investor, investor);
        vm.expectRevert(bytes("ERC7540Vault/not-the-owner"));
        vault.withdraw(redemption1, investor, investor);

        // fail: ward can not make requests on behalf of investor
        root.relyContract(vault_, self);
        vm.expectRevert(bytes("ERC7540Vault/not-the-owner"));
        vault.redeem(redemption1, investor, investor);
        vm.expectRevert(bytes("ERC7540Vault/not-the-owner"));
        vault.withdraw(redemption1, investor, investor);

        // investor redeems rest for himself
        vm.prank(investor);
        vault.redeem(redemption1, investor, investor);
        vm.prank(investor);
        vault.withdraw(redemption2, investor, investor);
    }

    function testCancelRedeemOrder(uint256 amount) public {
        amount = uint128(bound(amount, 2, MAX_UINT128 / 2));

        address vault_ = deploySimpleVault();
        ERC7540Vault vault = ERC7540Vault(vault_);
        TrancheTokenLike trancheToken = TrancheTokenLike(address(vault.share()));
        deposit(vault_, self, amount * 2); // deposit funds first

        vault.requestRedeem(amount, address(this), address(this), "");
        assertEq(trancheToken.balanceOf(address(escrow)), amount);
        assertEq(trancheToken.balanceOf(self), amount);

        // will fail - user not member
        centrifugeChain.updateMember(vault.poolId(), vault.trancheId(), self, uint64(block.timestamp));
        vm.warp(block.timestamp + 1);
        vm.expectRevert(bytes("InvestmentManager/transfer-not-allowed"));
        vault.cancelRedeemRequest(0, self);
        centrifugeChain.updateMember(vault.poolId(), vault.trancheId(), self, type(uint64).max);

        // check message was send out to centchain
        vault.cancelRedeemRequest(0, self);
        bytes memory cancelOrderMessage = abi.encodePacked(
            uint8(MessagesLib.Call.CancelRedeemOrder),
            vault.poolId(),
            vault.trancheId(),
            bytes32(bytes20(self)),
            defaultCurrencyId
        );
        assertEq(cancelOrderMessage, router1.values_bytes("send"));

        assertEq(vault.pendingCancelRedeemRequest(0, self), true);

        // Cannot cancel twice
        vm.expectRevert(bytes("InvestmentManager/cancellation-is-pending"));
        vault.cancelRedeemRequest(0, self);

        vm.expectRevert(bytes("InvestmentManager/cancellation-is-pending"));
        vault.requestRedeem(amount, address(this), address(this), "");

        centrifugeChain.isFulfilledCancelRedeemRequest(
            vault.poolId(), vault.trancheId(), self.toBytes32(), defaultCurrencyId, uint128(amount), uint128(amount)
        );

        assertEq(trancheToken.balanceOf(address(escrow)), amount);
        assertEq(trancheToken.balanceOf(self), amount);
        assertEq(vault.claimableCancelRedeemRequest(0, self), amount);
        assertEq(vault.pendingCancelRedeemRequest(0, self), false);

        // After cancellation is executed, new request can be submitted
        vault.requestRedeem(amount, address(this), address(this), "");
    }

    function testTriggerIncreaseRedeemOrderTokens(uint128 amount) public {
        amount = uint128(bound(amount, 2, (MAX_UINT128 - 1)));

        address vault_ = deploySimpleVault();
        ERC7540Vault vault = ERC7540Vault(vault_);
        TrancheTokenLike trancheToken = TrancheTokenLike(address(vault.share()));
        deposit(vault_, investor, amount, false); // request and execute deposit, but don't claim
        uint256 investorBalanceBefore = erc20.balanceOf(investor);
        assertEq(vault.maxMint(investor), amount);
        uint64 poolId = vault.poolId();
        bytes16 trancheId = vault.trancheId();

        vm.prank(investor);
        vault.mint(amount / 2, investor); // investor mints half of the amount

        assertApproxEqAbs(trancheToken.balanceOf(investor), amount / 2, 1);
        assertApproxEqAbs(trancheToken.balanceOf(address(escrow)), amount / 2, 1);
        assertApproxEqAbs(vault.maxMint(investor), amount / 2, 1);

        // Fail - Redeem amount too big
        vm.expectRevert(bytes("ERC20/insufficient-balance"));
        centrifugeChain.triggerIncreaseRedeemOrder(poolId, trancheId, investor, defaultCurrencyId, uint128(amount + 1));

        //Fail - Tranche token amount zero
        vm.expectRevert(bytes("InvestmentManager/tranche-token-amount-is-zero"));
        centrifugeChain.triggerIncreaseRedeemOrder(poolId, trancheId, investor, defaultCurrencyId, 0);

        // should work even if investor is frozen
        centrifugeChain.freeze(poolId, trancheId, investor); // freeze investor
        assertTrue(!TrancheToken(address(vault.share())).checkTransferRestriction(investor, address(escrow), amount));

        // half of the amount will be trabsferred from the investor's wallet & half of the amount will be taken from
        // escrow
        centrifugeChain.triggerIncreaseRedeemOrder(poolId, trancheId, investor, defaultCurrencyId, amount);

        assertApproxEqAbs(trancheToken.balanceOf(investor), 0, 1);
        assertApproxEqAbs(trancheToken.balanceOf(address(escrow)), amount, 1);
        assertEq(vault.maxMint(investor), 0);

        centrifugeChain.isFulfilledRedeemRequest(
            vault.poolId(),
            vault.trancheId(),
            bytes32(bytes20(investor)),
            defaultCurrencyId,
            uint128(amount),
            uint128(amount)
        );

        assertApproxEqAbs(trancheToken.balanceOf(address(escrow)), 0, 1);
        assertApproxEqAbs(erc20.balanceOf(address(escrow)), amount, 1);
        vm.prank(investor);
        vault.redeem(amount, investor, investor);
        assertApproxEqAbs(erc20.balanceOf(investor), investorBalanceBefore + amount, 1);
    }

    function testTriggerIncreaseRedeemOrderTokensUnmitedTokensInEscrow(uint128 amount) public {
        amount = uint128(bound(amount, 2, (MAX_UINT128 - 1)));

        address vault_ = deploySimpleVault();
        ERC7540Vault vault = ERC7540Vault(vault_);
        TrancheTokenLike trancheToken = TrancheTokenLike(address(vault.share()));
        deposit(vault_, investor, amount, false); // request and execute deposit, but don't claim
        uint256 investorBalanceBefore = erc20.balanceOf(investor);
        assertEq(vault.maxMint(investor), amount);
        uint64 poolId = vault.poolId();
        bytes16 trancheId = vault.trancheId();

        // Fail - Redeem amount too big
        vm.expectRevert(bytes("ERC20/insufficient-balance"));
        centrifugeChain.triggerIncreaseRedeemOrder(poolId, trancheId, investor, defaultCurrencyId, uint128(amount + 1));

        // should work even if investor is frozen
        centrifugeChain.freeze(poolId, trancheId, investor); // freeze investor
        assertTrue(!TrancheToken(address(vault.share())).checkTransferRestriction(investor, address(escrow), amount));

        // Test trigger partial redeem (maxMint > redeemAmount), where investor did not mint their tokens - user tokens
        // are still locked in escrow
        uint128 redeemAmount = uint128(amount / 2);
        centrifugeChain.triggerIncreaseRedeemOrder(poolId, trancheId, investor, defaultCurrencyId, redeemAmount);
        assertApproxEqAbs(trancheToken.balanceOf(address(escrow)), amount, 1);
        assertEq(trancheToken.balanceOf(investor), 0);

        // Test trigger full redeem (maxMint = redeemAmount), where investor did not mint their tokens - user tokens are
        // still locked in escrow
        redeemAmount = uint128(amount - redeemAmount);
        centrifugeChain.triggerIncreaseRedeemOrder(poolId, trancheId, investor, defaultCurrencyId, redeemAmount);
        assertApproxEqAbs(trancheToken.balanceOf(address(escrow)), amount, 1);
        assertEq(trancheToken.balanceOf(investor), 0);
        assertEq(vault.maxMint(investor), 0);

        centrifugeChain.isFulfilledRedeemRequest(
            vault.poolId(),
            vault.trancheId(),
            bytes32(bytes20(investor)),
            defaultCurrencyId,
            uint128(amount),
            uint128(amount)
        );

        assertApproxEqAbs(trancheToken.balanceOf(address(escrow)), 0, 1);
        assertApproxEqAbs(erc20.balanceOf(address(escrow)), amount, 1);
        vm.prank(investor);
        vault.redeem(amount, investor, investor);

        assertApproxEqAbs(erc20.balanceOf(investor), investorBalanceBefore + amount, 1);
    }

    function testPartialRedemptionExecutions() public {
        address vault_ = deploySimpleVault();
        ERC7540Vault vault = ERC7540Vault(vault_);
        TrancheTokenLike trancheToken = TrancheTokenLike(address(vault.share()));
        uint64 poolId = vault.poolId();
        bytes16 trancheId = vault.trancheId();
        address currency_ = address(vault.asset());
        ERC20 currency = ERC20(currency_);
        uint128 assetId = poolManager.assetToId(currency_);
        centrifugeChain.updateTrancheTokenPrice(
            poolId, trancheId, assetId, 1000000000000000000, uint64(block.timestamp)
        );

        // invest
        uint256 investmentAmount = 100000000; // 100 * 10**6
        centrifugeChain.updateMember(poolId, trancheId, self, type(uint64).max);
        currency.approve(address(investmentManager), investmentAmount);
        currency.mint(self, investmentAmount);
        erc20.approve(address(vault), investmentAmount);
        vault.requestDeposit(investmentAmount, self, self, "");
        uint128 _assetId = poolManager.assetToId(address(currency)); // retrieve assetId

        uint128 trancheTokenPayout = 100000000;
        centrifugeChain.isFulfilledDepositRequest(
            poolId,
            trancheId,
            bytes32(bytes20(self)),
            _assetId,
            uint128(investmentAmount),
            trancheTokenPayout,
            trancheTokenPayout
        );

        (, uint256 depositPrice,,,,,,,,,) = investmentManager.investments(address(vault), self);
        assertEq(depositPrice, 1000000000000000000);

        // assert deposit & mint values adjusted
        assertApproxEqAbs(vault.maxDeposit(self), investmentAmount, 2);
        assertEq(vault.maxMint(self), trancheTokenPayout);

        // collect the tranche tokens
        vault.mint(trancheTokenPayout, self);
        assertEq(trancheToken.balanceOf(self), trancheTokenPayout);

        // redeem
        vault.requestRedeem(trancheTokenPayout, self, self, "");

        // trigger first executed collectRedeem at a price of 1.5
        // user is able to redeem 50 tranche tokens, at 1.5 price, 75 currency is paid out
        uint128 currencyPayout = 75000000; // 150*10**6

        // mint approximate interest amount into escrow
        currency.mint(address(escrow), currencyPayout * 2 - investmentAmount);

        centrifugeChain.isFulfilledRedeemRequest(
            poolId, trancheId, bytes32(bytes20(self)), _assetId, currencyPayout, trancheTokenPayout / 2
        );

        (,,, uint256 redeemPrice,,,,,,,) = investmentManager.investments(address(vault), self);
        assertEq(redeemPrice, 1500000000000000000);

        // trigger second executed collectRedeem at a price of 1.0
        // user has 50 tranche tokens left, at 1.0 price, 50 currency is paid out
        currencyPayout = 50000000; // 50*10**6

        centrifugeChain.isFulfilledRedeemRequest(
            poolId, trancheId, bytes32(bytes20(self)), _assetId, currencyPayout, trancheTokenPayout / 2
        );

        (,,, redeemPrice,,,,,,,) = investmentManager.investments(address(vault), self);
        assertEq(redeemPrice, 1250000000000000000);
    }

    function partialRedeem(uint64 poolId, bytes16 trancheId, ERC7540Vault vault, ERC20 currency) public {
        TrancheTokenLike trancheToken = TrancheTokenLike(address(vault.share()));

        uint128 assetId = poolManager.assetToId(address(currency));
        uint256 totalTrancheTokens = trancheToken.balanceOf(self);
        uint256 redeemAmount = 50000000000000000000;
        assertTrue(redeemAmount <= totalTrancheTokens);
        vault.requestRedeem(redeemAmount, self, self, "");

        // first trigger executed collectRedeem of the first 25 trancheTokens at a price of 1.1
        uint128 firstTrancheTokenRedeem = 25000000000000000000;
        uint128 secondTrancheTokenRedeem = 25000000000000000000;
        assertEq(firstTrancheTokenRedeem + secondTrancheTokenRedeem, redeemAmount);
        uint128 firstCurrencyPayout = 27500000; // (25000000000000000000/10**18) * 10**6 * 1.1

        centrifugeChain.isFulfilledRedeemRequest(
            poolId, trancheId, bytes32(bytes20(self)), assetId, firstCurrencyPayout, firstTrancheTokenRedeem
        );

        assertEq(vault.maxRedeem(self), firstTrancheTokenRedeem);

        (,,, uint256 redeemPrice,,,,,,,) = investmentManager.investments(address(vault), self);
        assertEq(redeemPrice, 1100000000000000000);

        // second trigger executed collectRedeem of the second 25 trancheTokens at a price of 1.3
        uint128 secondCurrencyPayout = 32500000; // (25000000000000000000/10**18) * 10**6 * 1.3
        centrifugeChain.isFulfilledRedeemRequest(
            poolId, trancheId, bytes32(bytes20(self)), assetId, secondCurrencyPayout, secondTrancheTokenRedeem
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
