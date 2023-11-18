// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import "./../TestSetup.t.sol";

contract RedeemTest is TestSetup {
    function testRedeem(uint256 amount) public {
        amount = uint128(bound(amount, 2, MAX_UINT128 / 2));

        address lPool_ = deploySimplePool();
        LiquidityPool lPool = LiquidityPool(lPool_);
        deposit(lPool_, self, amount); // deposit funds first
        centrifugeChain.updateTrancheTokenPrice(
            lPool.poolId(), lPool.trancheId(), defaultCurrencyId, defaultPrice, uint64(block.timestamp)
        );

        // success
        lPool.requestRedeem(amount, address(this), address(this));
        assertEq(lPool.balanceOf(address(escrow)), amount);
        assertEq(lPool.pendingRedeemRequest(0, self), amount);

        // fail: no tokens left
        vm.expectRevert(bytes("LiquidityPool/insufficient-balance"));
        lPool.requestRedeem(amount, address(this), address(this));

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
        assertEq(lPool.balanceOf(address(escrow)), 0);
        assertEq(erc20.balanceOf(address(userEscrow)), currencyPayout);

        // success
        lPool.redeem(amount / 2, self, self); // redeem half the amount to own wallet

        // fail -> investor has no approval to receive funds
        vm.expectRevert(bytes("UserEscrow/receiver-has-no-allowance"));
        lPool.redeem(amount / 2, investor, self); // redeem half the amount to another wallet

        // fail -> receiver needs to have max approval
        erc20.approve(investor, lPool.maxRedeem(self));
        vm.expectRevert(bytes("UserEscrow/receiver-has-no-allowance"));
        lPool.redeem(amount / 2, investor, self); // redeem half the amount to investor wallet

        // success
        erc20.approve(investor, type(uint256).max);
        lPool.redeem(amount / 2, investor, self); // redeem half the amount to investor wallet

        assertEq(lPool.balanceOf(self), 0);
        assertTrue(lPool.balanceOf(address(escrow)) <= 1);
        assertTrue(erc20.balanceOf(address(userEscrow)) <= 1);

        assertApproxEqAbs(erc20.balanceOf(self), (amount / 2), 1);
        assertApproxEqAbs(erc20.balanceOf(investor), (amount / 2), 1);
        assertTrue(lPool.maxWithdraw(self) <= 1);
        assertTrue(lPool.maxRedeem(self) <= 1);
    }

    function testWithdraw(uint256 amount) public {
        amount = uint128(bound(amount, 2, MAX_UINT128 / 2));

        address lPool_ = deploySimplePool();
        LiquidityPool lPool = LiquidityPool(lPool_);

        deposit(lPool_, self, amount); // deposit funds first
        centrifugeChain.updateTrancheTokenPrice(
            lPool.poolId(), lPool.trancheId(), defaultCurrencyId, defaultPrice, uint64(block.timestamp)
        );

        lPool.requestRedeem(amount, address(this), address(this));
        assertEq(lPool.balanceOf(address(escrow)), amount);
        assertEq(erc20.balanceOf(address(userEscrow)), 0);
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
        assertEq(lPool.balanceOf(address(escrow)), 0);
        assertEq(erc20.balanceOf(address(userEscrow)), currencyPayout);

        lPool.withdraw(amount / 2, self, self); // withdraw half the amount

        // fail -> investor has no approval to receive funds
        vm.expectRevert(bytes("UserEscrow/receiver-has-no-allowance"));
        lPool.withdraw(amount / 2, investor, self); // redeem half the amount to another wallet

        // fail -> receiver needs to have max approval
        erc20.approve(investor, lPool.maxWithdraw(self));
        vm.expectRevert(bytes("UserEscrow/receiver-has-no-allowance"));
        lPool.withdraw(amount / 2, investor, self); // redeem half the amount to investor wallet

        // success
        erc20.approve(investor, type(uint256).max);
        lPool.withdraw(amount / 2, investor, self); // redeem half the amount to investor wallet

        assertTrue(lPool.balanceOf(self) <= 1);
        assertTrue(erc20.balanceOf(address(userEscrow)) <= 1);
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

        deposit(lPool_, investor, amount); // deposit funds first // deposit funds first

        // investor can requestRedeem
        vm.prank(investor);
        lPool.requestRedeem(amount, investor, investor);

        uint128 tokenAmount = uint128(lPool.balanceOf(address(escrow)));
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
        vm.expectRevert(bytes("LiquidityPool/not-the-operator"));
        lPool.redeem(redemption1, investor, investor);
        vm.expectRevert(bytes("LiquidityPool/not-the-operator"));
        lPool.withdraw(redemption1, investor, investor);

        // fail: ward can not make requests on behalf of investor
        root.relyContract(lPool_, self);
        vm.expectRevert(bytes("LiquidityPool/not-the-operator"));
        lPool.redeem(redemption1, investor, investor);
        vm.expectRevert(bytes("LiquidityPool/not-the-operator"));
        lPool.withdraw(redemption1, investor, investor);

        // investor redeems rest for himself
        vm.prank(investor);
        lPool.redeem(redemption1, investor, investor);
        vm.prank(investor);
        lPool.withdraw(redemption2, investor, investor);
    }

    function testCancelRedeemOrder(uint256 amount) public {
        amount = uint128(bound(amount, 2, MAX_UINT128));

        address lPool_ = deploySimplePool();
        LiquidityPool lPool = LiquidityPool(lPool_);
        deposit(lPool_, self, amount); // deposit funds first

        lPool.requestRedeem(amount, address(this), address(this));
        assertEq(lPool.balanceOf(address(escrow)), amount);
        assertEq(lPool.balanceOf(self), 0);

        // check message was send out to centchain
        lPool.cancelRedeemRequest();
        bytes memory cancelOrderMessage = Messages.formatCancelRedeemOrder(
            lPool.poolId(), lPool.trancheId(), _addressToBytes32(self), defaultCurrencyId
        );
        assertEq(cancelOrderMessage, router.values_bytes("send"));

        centrifugeChain.isExecutedDecreaseRedeemOrder(
            lPool.poolId(), lPool.trancheId(), _addressToBytes32(self), defaultCurrencyId, uint128(amount), 0
        );

        assertEq(lPool.balanceOf(address(escrow)), amount);
        assertEq(lPool.balanceOf(self), 0);
        assertEq(lPool.maxDeposit(self), amount);
        assertEq(lPool.maxMint(self), amount);
    }

    function testDecreaseRedeemRequest(uint256 amount, uint256 decreaseAmount) public {
        decreaseAmount = uint128(bound(decreaseAmount, 2, MAX_UINT128 - 1));
        amount = uint128(bound(amount, decreaseAmount + 1, MAX_UINT128)); // amount > decreaseAmount

        address lPool_ = deploySimplePool();
        LiquidityPool lPool = LiquidityPool(lPool_);
        centrifugeChain.updateTrancheTokenPrice(
            lPool.poolId(), lPool.trancheId(), defaultCurrencyId, defaultPrice, uint64(block.timestamp)
        );
        deposit(lPool_, self, amount);
        lPool.requestRedeem(amount, address(this), address(this));

        assertEq(lPool.balanceOf(address(escrow)), amount);
        assertEq(lPool.balanceOf(self), 0);

        // decrease redeem request
        lPool.decreaseRedeemRequest(decreaseAmount);
        centrifugeChain.isExecutedDecreaseRedeemOrder(
            lPool.poolId(), lPool.trancheId(), bytes32(bytes20(self)), defaultCurrencyId, uint128(decreaseAmount), 0
        );

        assertEq(lPool.balanceOf(address(escrow)), amount);
        assertEq(lPool.balanceOf(self), 0);
        assertEq(lPool.maxDeposit(self), decreaseAmount);
        assertEq(lPool.maxMint(self), decreaseAmount);
    }

    function testTriggerIncreaseRedeemOrderTokens(uint128 amount) public {
        amount = uint128(bound(amount, 2, (MAX_UINT128 - 1)));

        address lPool_ = deploySimplePool();
        LiquidityPool lPool = LiquidityPool(lPool_);
        deposit(lPool_, investor, amount, false); // request and execute deposit, but don't claim
        uint256 investorBalanceBefore = erc20.balanceOf(investor);
        assertEq(lPool.maxMint(investor), amount);
        uint64 poolId = lPool.poolId();
        bytes16 trancheId = lPool.trancheId();

        vm.prank(investor);
        lPool.mint(amount / 2, investor); // investor mints half of the amount

        assertApproxEqAbs(lPool.balanceOf(investor), amount / 2, 1);
        assertApproxEqAbs(lPool.balanceOf(address(escrow)), amount / 2, 1);
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

        assertApproxEqAbs(lPool.balanceOf(investor), 0, 1);
        assertApproxEqAbs(lPool.balanceOf(address(escrow)), amount, 1);
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

        assertApproxEqAbs(lPool.balanceOf(address(escrow)), 0, 1);
        assertApproxEqAbs(erc20.balanceOf(address(userEscrow)), amount, 1);
        vm.prank(investor);
        lPool.redeem(amount, investor, investor);
        assertApproxEqAbs(erc20.balanceOf(investor), investorBalanceBefore + amount, 1);
    }

    function testTriggerIncreaseRedeemOrderTokensUnmitedTokensInEscrow(uint128 amount) public {
        amount = uint128(bound(amount, 2, (MAX_UINT128 - 1)));

        address lPool_ = deploySimplePool();
        LiquidityPool lPool = LiquidityPool(lPool_);
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
        assertApproxEqAbs(lPool.balanceOf(address(escrow)), amount, 1);
        assertEq(lPool.balanceOf(investor), 0);

        // Test trigger full redeem (maxMint = redeemAmount), where investor did not mint their tokens - user tokens are
        // still locked in escrow
        redeemAmount = uint128(amount - redeemAmount);
        centrifugeChain.triggerIncreaseRedeemOrder(poolId, trancheId, investor, defaultCurrencyId, redeemAmount);
        assertApproxEqAbs(lPool.balanceOf(address(escrow)), amount, 1);
        assertEq(lPool.balanceOf(investor), 0);
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

        assertApproxEqAbs(lPool.balanceOf(address(escrow)), 0, 1);
        assertApproxEqAbs(erc20.balanceOf(address(userEscrow)), amount, 1);
        vm.prank(investor);
        lPool.redeem(amount, investor, investor);

        assertApproxEqAbs(erc20.balanceOf(investor), investorBalanceBefore + amount, 1);
    }
}
