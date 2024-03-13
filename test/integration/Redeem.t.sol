// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import "./../BaseTest.sol";
import {CastLib} from "src/libraries/CastLib.sol";

contract RedeemTest is BaseTest {
    using CastLib for *;

    function testRedeem(uint256 amount) public {
        amount = uint128(bound(amount, 2, MAX_UINT128 / 2));

        address lPool_ = deploySimplePool();
        LiquidityPool lPool = LiquidityPool(lPool_);
        TrancheTokenLike trancheToken = TrancheTokenLike(address(lPool.share()));

        deposit(lPool_, self, amount); // deposit funds first
        centrifugeChain.updateTrancheTokenPrice(
            lPool.poolId(), lPool.trancheId(), defaultCurrencyId, defaultPrice, uint64(block.timestamp)
        );

        // will fail - zero deposit not allowed
        vm.expectRevert(bytes("InvestmentManager/zero-amount-not-allowed"));
        lPool.requestRedeem(0, self, self, "");

        // will fail - investment currency not allowed
        centrifugeChain.disallowInvestmentCurrency(lPool.poolId(), defaultCurrencyId);
        vm.expectRevert(bytes("InvestmentManager/currency-not-allowed"));
        lPool.requestRedeem(amount, address(this), address(this), "");

        // success
        centrifugeChain.allowInvestmentCurrency(lPool.poolId(), defaultCurrencyId);
        lPool.requestRedeem(amount, address(this), address(this), "");
        assertEq(trancheToken.balanceOf(address(escrow)), amount);
        assertEq(lPool.pendingRedeemRequest(0, self), amount);
        assertEq(lPool.claimableRedeemRequest(0, self), 0);

        // fail: no tokens left
        vm.expectRevert(bytes("LiquidityPool/insufficient-balance"));
        lPool.requestRedeem(amount, address(this), address(this), "");

        // trigger executed collectRedeem
        uint128 _currencyId = poolManager.currencyAddressToId(address(erc20)); // retrieve currencyId
        uint128 currencyPayout = uint128((amount * 10 ** 18) / defaultPrice);
        centrifugeChain.isExecutedCollectRedeem(
            lPool.poolId(), lPool.trancheId(), bytes32(bytes20(self)), _currencyId, currencyPayout, uint128(amount), 0
        );

        // assert withdraw & redeem values adjusted
        assertEq(lPool.maxWithdraw(self), currencyPayout); // max deposit
        assertEq(lPool.maxRedeem(self), amount); // max deposit
        assertEq(lPool.pendingRedeemRequest(0, self), 0);
        assertEq(lPool.claimableRedeemRequest(0, self), amount);
        assertEq(trancheToken.balanceOf(address(escrow)), 0);
        assertEq(erc20.balanceOf(address(escrow)), currencyPayout);

        // can redeem to self
        lPool.redeem(amount / 2, self, self); // redeem half the amount to own wallet

        // can also redeem to another user
        lPool.redeem(amount / 2, investor, self); // redeem half the amount to investor wallet

        assertEq(trancheToken.balanceOf(self), 0);
        assertTrue(trancheToken.balanceOf(address(escrow)) <= 1);
        assertTrue(erc20.balanceOf(address(escrow)) <= 1);

        assertApproxEqAbs(erc20.balanceOf(self), (amount / 2), 1);
        assertApproxEqAbs(erc20.balanceOf(investor), (amount / 2), 1);
        assertTrue(lPool.maxWithdraw(self) <= 1);
        assertTrue(lPool.maxRedeem(self) <= 1);

        // withdrawing or redeeming more should revert
        vm.expectRevert(bytes("InvestmentManager/exceeds-redeem-limits"));
        lPool.withdraw(2, investor, self);
        vm.expectRevert(bytes("InvestmentManager/exceeds-redeem-limits"));
        lPool.redeem(2, investor, self);
    }

    function testWithdraw(uint256 amount) public {
        amount = uint128(bound(amount, 2, MAX_UINT128 / 2));

        address lPool_ = deploySimplePool();
        LiquidityPool lPool = LiquidityPool(lPool_);
        TrancheTokenLike trancheToken = TrancheTokenLike(address(lPool.share()));

        deposit(lPool_, self, amount); // deposit funds first
        centrifugeChain.updateTrancheTokenPrice(
            lPool.poolId(), lPool.trancheId(), defaultCurrencyId, defaultPrice, uint64(block.timestamp)
        );

        lPool.requestRedeem(amount, address(this), address(this), "");
        assertEq(trancheToken.balanceOf(address(escrow)), amount);
        assertGt(lPool.pendingRedeemRequest(0, self), 0);

        // trigger executed collectRedeem
        uint128 _currencyId = poolManager.currencyAddressToId(address(erc20)); // retrieve currencyId
        uint128 currencyPayout = uint128((amount * 10 ** 18) / defaultPrice);
        centrifugeChain.isExecutedCollectRedeem(
            lPool.poolId(), lPool.trancheId(), bytes32(bytes20(self)), _currencyId, currencyPayout, uint128(amount), 0
        );

        // assert withdraw & redeem values adjusted
        assertEq(lPool.maxWithdraw(self), currencyPayout); // max deposit
        assertEq(lPool.maxRedeem(self), amount); // max deposit
        assertEq(trancheToken.balanceOf(address(escrow)), 0);
        assertEq(erc20.balanceOf(address(escrow)), currencyPayout);

        // can redeem to self
        lPool.withdraw(amount / 2, self, self); // redeem half the amount to own wallet

        // can also withdraw to another user
        lPool.withdraw(amount / 2, investor, self); // redeem half the amount to investor wallet

        assertTrue(trancheToken.balanceOf(self) <= 1);
        assertTrue(erc20.balanceOf(address(escrow)) <= 1);
        assertApproxEqAbs(erc20.balanceOf(self), currencyPayout / 2, 1);
        assertApproxEqAbs(erc20.balanceOf(investor), currencyPayout / 2, 1);
        assertTrue(lPool.maxRedeem(self) <= 1);
        assertTrue(lPool.maxWithdraw(self) <= 1);
    }

    function testRedeemWithApproval(uint256 redemption1, uint256 redemption2) public {
        redemption1 = uint128(bound(redemption1, 2, MAX_UINT128 / 4));
        redemption2 = uint128(bound(redemption2, 2, MAX_UINT128 / 4));
        uint256 amount = redemption1 + redemption2;
        vm.assume(amountAssumption(amount));

        address lPool_ = deploySimplePool();
        LiquidityPool lPool = LiquidityPool(lPool_);
        TrancheTokenLike trancheToken = TrancheTokenLike(address(lPool.share()));

        deposit(lPool_, investor, amount); // deposit funds first // deposit funds first

        // investor can requestRedeem
        vm.prank(investor);
        lPool.requestRedeem(amount, investor, investor, "");

        uint128 tokenAmount = uint128(trancheToken.balanceOf(address(escrow)));
        centrifugeChain.isExecutedCollectRedeem(
            lPool.poolId(),
            lPool.trancheId(),
            bytes32(bytes20(investor)),
            defaultCurrencyId,
            uint128(amount),
            uint128(tokenAmount),
            0
        );

        assertEq(lPool.maxRedeem(investor), tokenAmount);
        assertEq(lPool.maxWithdraw(investor), uint128(amount));

        // test for both scenarios redeem & withdraw

        // fail: self cannot redeem for investor
        vm.expectRevert(bytes("LiquidityPool/not-the-owner"));
        lPool.redeem(redemption1, investor, investor);
        vm.expectRevert(bytes("LiquidityPool/not-the-owner"));
        lPool.withdraw(redemption1, investor, investor);

        // fail: ward can not make requests on behalf of investor
        root.relyContract(lPool_, self);
        vm.expectRevert(bytes("LiquidityPool/not-the-owner"));
        lPool.redeem(redemption1, investor, investor);
        vm.expectRevert(bytes("LiquidityPool/not-the-owner"));
        lPool.withdraw(redemption1, investor, investor);

        // investor redeems rest for himself
        vm.prank(investor);
        lPool.redeem(redemption1, investor, investor);
        vm.prank(investor);
        lPool.withdraw(redemption2, investor, investor);
    }

    function testCancelRedeemOrder(uint256 amount) public {
        amount = uint128(bound(amount, 2, MAX_UINT128 / 2));

        address lPool_ = deploySimplePool();
        LiquidityPool lPool = LiquidityPool(lPool_);
        TrancheTokenLike trancheToken = TrancheTokenLike(address(lPool.share()));
        deposit(lPool_, self, amount * 2); // deposit funds first

        lPool.requestRedeem(amount, address(this), address(this), "");
        assertEq(trancheToken.balanceOf(address(escrow)), amount);
        assertEq(trancheToken.balanceOf(self), amount);

        // will fail - user not member
        centrifugeChain.updateMember(lPool.poolId(), lPool.trancheId(), self, uint64(block.timestamp));
        vm.warp(block.timestamp + 1);
        vm.expectRevert(bytes("InvestmentManager/transfer-not-allowed"));
        lPool.cancelRedeemRequest();
        centrifugeChain.updateMember(lPool.poolId(), lPool.trancheId(), self, type(uint64).max);

        // check message was send out to centchain
        lPool.cancelRedeemRequest();
        bytes memory cancelOrderMessage = abi.encodePacked(
            uint8(MessagesLib.Call.CancelRedeemOrder),
            lPool.poolId(),
            lPool.trancheId(),
            bytes32(bytes20(self)),
            defaultCurrencyId
        );
        assertEq(cancelOrderMessage, router1.values_bytes("send"));

        assertEq(lPool.pendingCancelRedeemRequest(0, self), true);

        // Cannot cancel twice
        vm.expectRevert(bytes("InvestmentManager/cancellation-is-pending"));
        lPool.cancelRedeemRequest();

        vm.expectRevert(bytes("InvestmentManager/cancellation-is-pending"));
        lPool.requestRedeem(amount, address(this), address(this), "");

        centrifugeChain.isExecutedDecreaseRedeemOrder(
            lPool.poolId(), lPool.trancheId(), self.toBytes32(), defaultCurrencyId, uint128(amount), 0
        );

        assertEq(trancheToken.balanceOf(address(escrow)), amount);
        assertEq(trancheToken.balanceOf(self), amount);
        assertEq(lPool.maxDeposit(self), amount);
        assertEq(lPool.maxMint(self), amount);
        assertEq(lPool.pendingCancelRedeemRequest(0, self), false);

        // After cancellation is executed, new request can be submitted
        lPool.requestRedeem(amount, address(this), address(this), "");
    }

    function testTriggerIncreaseRedeemOrderTokens(uint128 amount) public {
        amount = uint128(bound(amount, 2, (MAX_UINT128 - 1)));

        address lPool_ = deploySimplePool();
        LiquidityPool lPool = LiquidityPool(lPool_);
        TrancheTokenLike trancheToken = TrancheTokenLike(address(lPool.share()));
        deposit(lPool_, investor, amount, false); // request and execute deposit, but don't claim
        uint256 investorBalanceBefore = erc20.balanceOf(investor);
        assertEq(lPool.maxMint(investor), amount);
        uint64 poolId = lPool.poolId();
        bytes16 trancheId = lPool.trancheId();

        vm.prank(investor);
        lPool.mint(amount / 2, investor); // investor mints half of the amount

        assertApproxEqAbs(trancheToken.balanceOf(investor), amount / 2, 1);
        assertApproxEqAbs(trancheToken.balanceOf(address(escrow)), amount / 2, 1);
        assertApproxEqAbs(lPool.maxMint(investor), amount / 2, 1);

        // Fail - Redeem amount too big
        vm.expectRevert(bytes("ERC20/insufficient-balance"));
        centrifugeChain.triggerIncreaseRedeemOrder(poolId, trancheId, investor, defaultCurrencyId, uint128(amount + 1));

        //Fail - Tranche token amount zero
        vm.expectRevert(bytes("InvestmentManager/tranche-token-amount-is-zero"));
        centrifugeChain.triggerIncreaseRedeemOrder(poolId, trancheId, investor, defaultCurrencyId, 0);

        // should work even if investor is frozen
        centrifugeChain.freeze(poolId, trancheId, investor); // freeze investor
        assertTrue(!TrancheToken(address(lPool.share())).checkTransferRestriction(investor, address(escrow), amount));

        // half of the amount will be trabsferred from the investor's wallet & half of the amount will be taken from
        // escrow
        centrifugeChain.triggerIncreaseRedeemOrder(poolId, trancheId, investor, defaultCurrencyId, amount);

        assertApproxEqAbs(trancheToken.balanceOf(investor), 0, 1);
        assertApproxEqAbs(trancheToken.balanceOf(address(escrow)), amount, 1);
        assertEq(lPool.maxMint(investor), 0);

        centrifugeChain.isExecutedCollectRedeem(
            lPool.poolId(),
            lPool.trancheId(),
            bytes32(bytes20(investor)),
            defaultCurrencyId,
            uint128(amount),
            uint128(amount),
            uint128(amount)
        );

        assertApproxEqAbs(trancheToken.balanceOf(address(escrow)), 0, 1);
        assertApproxEqAbs(erc20.balanceOf(address(escrow)), amount, 1);
        vm.prank(investor);
        lPool.redeem(amount, investor, investor);
        assertApproxEqAbs(erc20.balanceOf(investor), investorBalanceBefore + amount, 1);
    }

    function testTriggerIncreaseRedeemOrderTokensUnmitedTokensInEscrow(uint128 amount) public {
        amount = uint128(bound(amount, 2, (MAX_UINT128 - 1)));

        address lPool_ = deploySimplePool();
        LiquidityPool lPool = LiquidityPool(lPool_);
        TrancheTokenLike trancheToken = TrancheTokenLike(address(lPool.share()));
        deposit(lPool_, investor, amount, false); // request and execute deposit, but don't claim
        uint256 investorBalanceBefore = erc20.balanceOf(investor);
        assertEq(lPool.maxMint(investor), amount);
        uint64 poolId = lPool.poolId();
        bytes16 trancheId = lPool.trancheId();

        // Fail - Redeem amount too big
        vm.expectRevert(bytes("ERC20/insufficient-balance"));
        centrifugeChain.triggerIncreaseRedeemOrder(poolId, trancheId, investor, defaultCurrencyId, uint128(amount + 1));

        // should work even if investor is frozen
        centrifugeChain.freeze(poolId, trancheId, investor); // freeze investor
        assertTrue(!TrancheToken(address(lPool.share())).checkTransferRestriction(investor, address(escrow), amount));

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
        assertEq(lPool.maxMint(investor), 0);

        centrifugeChain.isExecutedCollectRedeem(
            lPool.poolId(),
            lPool.trancheId(),
            bytes32(bytes20(investor)),
            defaultCurrencyId,
            uint128(amount),
            uint128(amount),
            uint128(amount)
        );

        assertApproxEqAbs(trancheToken.balanceOf(address(escrow)), 0, 1);
        assertApproxEqAbs(erc20.balanceOf(address(escrow)), amount, 1);
        vm.prank(investor);
        lPool.redeem(amount, investor, investor);

        assertApproxEqAbs(erc20.balanceOf(investor), investorBalanceBefore + amount, 1);
    }

    function testPartialRedemptionExecutions() public {
        address lPool_ = deploySimplePool();
        LiquidityPool lPool = LiquidityPool(lPool_);
        TrancheTokenLike trancheToken = TrancheTokenLike(address(lPool.share()));
        uint64 poolId = lPool.poolId();
        bytes16 trancheId = lPool.trancheId();
        address currency_ = address(lPool.asset());
        ERC20 currency = ERC20(currency_);
        uint128 currencyId = poolManager.currencyAddressToId(currency_);
        centrifugeChain.updateTrancheTokenPrice(
            poolId, trancheId, currencyId, 1000000000000000000, uint64(block.timestamp)
        );

        // invest
        uint256 investmentAmount = 100000000; // 100 * 10**6
        centrifugeChain.updateMember(poolId, trancheId, self, type(uint64).max);
        currency.approve(address(investmentManager), investmentAmount);
        currency.mint(self, investmentAmount);
        erc20.approve(address(lPool), investmentAmount);
        lPool.requestDeposit(investmentAmount, self, self, "");
        uint128 _currencyId = poolManager.currencyAddressToId(address(currency)); // retrieve currencyId

        uint128 trancheTokenPayout = 100000000;
        centrifugeChain.isExecutedCollectInvest(
            poolId, trancheId, bytes32(bytes20(self)), _currencyId, uint128(investmentAmount), trancheTokenPayout, 0
        );

        (, uint256 depositPrice,,,,,,,) = investmentManager.investments(address(lPool), self);
        assertEq(depositPrice, 1000000000000000000);

        // assert deposit & mint values adjusted
        assertApproxEqAbs(lPool.maxDeposit(self), investmentAmount, 2);
        assertEq(lPool.maxMint(self), trancheTokenPayout);

        // collect the tranche tokens
        lPool.mint(trancheTokenPayout, self);
        assertEq(trancheToken.balanceOf(self), trancheTokenPayout);

        // redeem
        lPool.requestRedeem(trancheTokenPayout, self, self, "");

        // trigger first executed collectRedeem at a price of 1.5
        // user is able to redeem 50 tranche tokens, at 1.5 price, 75 currency is paid out
        uint128 currencyPayout = 75000000; // 150*10**6

        // mint approximate interest amount into escrow
        currency.mint(address(escrow), currencyPayout * 2 - investmentAmount);

        centrifugeChain.isExecutedCollectRedeem(
            poolId,
            trancheId,
            bytes32(bytes20(self)),
            _currencyId,
            currencyPayout,
            trancheTokenPayout / 2,
            trancheTokenPayout / 2
        );

        (,,, uint256 redeemPrice,,,,,) = investmentManager.investments(address(lPool), self);
        assertEq(redeemPrice, 1500000000000000000);

        // trigger second executed collectRedeem at a price of 1.0
        // user has 50 tranche tokens left, at 1.0 price, 50 currency is paid out
        currencyPayout = 50000000; // 50*10**6

        centrifugeChain.isExecutedCollectRedeem(
            poolId, trancheId, bytes32(bytes20(self)), _currencyId, currencyPayout, trancheTokenPayout / 2, 0
        );

        (,,, redeemPrice,,,,,) = investmentManager.investments(address(lPool), self);
        assertEq(redeemPrice, 1250000000000000000);
    }

    function partialRedeem(uint64 poolId, bytes16 trancheId, LiquidityPool lPool, ERC20 currency) public {
        TrancheTokenLike trancheToken = TrancheTokenLike(address(lPool.share()));

        uint128 currencyId = poolManager.currencyAddressToId(address(currency));
        uint256 totalTrancheTokens = trancheToken.balanceOf(self);
        uint256 redeemAmount = 50000000000000000000;
        assertTrue(redeemAmount <= totalTrancheTokens);
        lPool.requestRedeem(redeemAmount, self, self, "");

        // first trigger executed collectRedeem of the first 25 trancheTokens at a price of 1.1
        uint128 firstTrancheTokenRedeem = 25000000000000000000;
        uint128 secondTrancheTokenRedeem = 25000000000000000000;
        assertEq(firstTrancheTokenRedeem + secondTrancheTokenRedeem, redeemAmount);
        uint128 firstCurrencyPayout = 27500000; // (25000000000000000000/10**18) * 10**6 * 1.1

        centrifugeChain.isExecutedCollectRedeem(
            poolId,
            trancheId,
            bytes32(bytes20(self)),
            currencyId,
            firstCurrencyPayout,
            firstTrancheTokenRedeem,
            secondTrancheTokenRedeem
        );

        assertEq(lPool.maxRedeem(self), firstTrancheTokenRedeem);

        (,,, uint256 redeemPrice,,,,,) = investmentManager.investments(address(lPool), self);
        assertEq(redeemPrice, 1100000000000000000);

        // second trigger executed collectRedeem of the second 25 trancheTokens at a price of 1.3
        uint128 secondCurrencyPayout = 32500000; // (25000000000000000000/10**18) * 10**6 * 1.3
        centrifugeChain.isExecutedCollectRedeem(
            poolId, trancheId, bytes32(bytes20(self)), currencyId, secondCurrencyPayout, secondTrancheTokenRedeem, 0
        );

        (,,, redeemPrice,,,,,) = investmentManager.investments(address(lPool), self);
        assertEq(redeemPrice, 1200000000000000000);

        assertApproxEqAbs(lPool.maxWithdraw(self), firstCurrencyPayout + secondCurrencyPayout, 2);
        assertEq(lPool.maxRedeem(self), redeemAmount);

        // collect the currency
        lPool.redeem(redeemAmount, self, self);
        assertEq(trancheToken.balanceOf(self), totalTrancheTokens - redeemAmount);
        assertEq(currency.balanceOf(self), firstCurrencyPayout + secondCurrencyPayout);
    }
}
