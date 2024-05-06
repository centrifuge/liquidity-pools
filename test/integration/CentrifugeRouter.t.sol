// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import "./../BaseTest.sol";

contract LiquidityPoolRouter is BaseTest {
    function testDeposit(uint256 amount) public {
        // amount = uint128(bound(amount, 4, MAX_UINT128));
        // vm.assume(amount % 2 == 0);

        // address lPool_ = deploySimplePool();
        // LiquidityPool lPool = LiquidityPool(lPool_);

        // erc20.mint(self, amount);

        // // will fail - user not member: can not send funds
        // vm.expectRevert(bytes("InvestmentManager/owner-is-restricted"));
        // lPool.requestDeposit(amount, self, self, "");

        // centrifugeChain.updateMember(lPool.poolId(), lPool.trancheId(), self, type(uint64).max); // add user as
        // member

        // // will fail - user not member: can not receive trancheToken
        // vm.expectRevert(bytes("InvestmentManager/transfer-not-allowed"));
        // lPool.requestDeposit(amount, nonMember, self, "");

        // // will fail - user did not give currency allowance to liquidity pool
        // vm.expectRevert(bytes("SafeTransferLib/safe-transfer-from-failed"));
        // lPool.requestDeposit(amount, self, self, "");

        // // will fail - zero deposit not allowed
        // vm.expectRevert(bytes("InvestmentManager/zero-amount-not-allowed"));
        // lPool.requestDeposit(0, self, self, "");

        // // will fail - owner != msg.sender not allowed
        // vm.expectRevert(bytes("LiquidityPool/not-msg-sender"));
        // lPool.requestDeposit(amount, self, nonMember, "");

        // // will fail - investment currency not allowed
        // centrifugeChain.disallowInvestmentCurrency(lPool.poolId(), defaultCurrencyId);
        // vm.expectRevert(bytes("InvestmentManager/currency-not-allowed"));
        // lPool.requestDeposit(amount, self, self, "");

        // // success
        // centrifugeChain.allowInvestmentCurrency(lPool.poolId(), defaultCurrencyId);
        // erc20.approve(lPool_, amount);
        // lPool.requestDeposit(amount, self, self, "");

        // // fail: no currency left
        // vm.expectRevert(bytes("LiquidityPool/insufficient-balance"));
        // lPool.requestDeposit(amount, self, self, "");

        // // ensure funds are locked in escrow
        // assertEq(erc20.balanceOf(address(escrow)), amount);
        // assertEq(erc20.balanceOf(self), 0);
        // assertEq(lPool.pendingDepositRequest(0, self), amount);
        // assertEq(lPool.claimableDepositRequest(0, self), 0);

        // // trigger executed collectInvest
        // uint128 _currencyId = poolManager.currencyAddressToId(address(erc20)); // retrieve currencyId
        // uint128 trancheTokensPayout = uint128((amount * 10 ** 18) / price); // trancheTokenPrice = 2$
        // assertApproxEqAbs(trancheTokensPayout, amount / 2, 2);
        // centrifugeChain.isExecutedCollectInvest(
        //     lPool.poolId(),
        //     lPool.trancheId(),
        //     bytes32(bytes20(self)),
        //     _currencyId,
        //     uint128(amount),
        //     trancheTokensPayout,
        //     uint128(amount)
    }

    function testDepositWithlock(uint256 amount) public {}

    function testRedeem(uint256 amount) public {
        //  amount = uint128(bound(amount, 2, MAX_UINT128 / 2));

        // address lPool_ = deploySimplePool();
        // LiquidityPool lPool = LiquidityPool(lPool_);
        // TrancheTokenLike trancheToken = TrancheTokenLike(address(lPool.share()));

        // deposit(lPool_, self, amount); // deposit funds first
        // centrifugeChain.updateTrancheTokenPrice(
        //     lPool.poolId(), lPool.trancheId(), defaultCurrencyId, defaultPrice, uint64(block.timestamp)
        // );

        // // will fail - zero deposit not allowed
        // vm.expectRevert(bytes("InvestmentManager/zero-amount-not-allowed"));
        // lPool.requestRedeem(0, self, self, "");

        // // will fail - investment currency not allowed
        // centrifugeChain.disallowInvestmentCurrency(lPool.poolId(), defaultCurrencyId);
        // vm.expectRevert(bytes("InvestmentManager/currency-not-allowed"));
        // lPool.requestRedeem(amount, address(this), address(this), "");

        // // success
        // centrifugeChain.allowInvestmentCurrency(lPool.poolId(), defaultCurrencyId);
        // lPool.requestRedeem(amount, address(this), address(this), "");
        // assertEq(trancheToken.balanceOf(address(escrow)), amount);
        // assertEq(lPool.pendingRedeemRequest(0, self), amount);
        // assertEq(lPool.claimableRedeemRequest(0, self), 0);

        // // fail: no tokens left
        // vm.expectRevert(bytes("LiquidityPool/insufficient-balance"));
        // lPool.requestRedeem(amount, address(this), address(this), "");

        // // trigger executed collectRedeem
        // uint128 _currencyId = poolManager.currencyAddressToId(address(erc20)); // retrieve currencyId
        // uint128 currencyPayout = uint128((amount * 10 ** 18) / defaultPrice);
        // centrifugeChain.isExecutedCollectRedeem(
        //     lPool.poolId(), lPool.trancheId(), bytes32(bytes20(self)), _currencyId, currencyPayout, uint128(amount)
        // );

        // // assert withdraw & redeem values adjusted
        // assertEq(lPool.maxWithdraw(self), currencyPayout); // max deposit
        // assertEq(lPool.maxRedeem(self), amount); // max deposit
        // assertEq(lPool.pendingRedeemRequest(0, self), 0);
        // assertEq(lPool.claimableRedeemRequest(0, self), amount);
        // assertEq(trancheToken.balanceOf(address(escrow)), 0);
        // assertEq(erc20.balanceOf(address(escrow)), currencyPayout);

        // // can redeem to self
        // lPool.redeem(amount / 2, self, self); // redeem half the amount to own wallet

        // // can also redeem to another user
        // lPool.redeem(amount / 2, investor, self); // redeem half the amount to investor wallet

        // assertEq(trancheToken.balanceOf(self), 0);
        // assertTrue(trancheToken.balanceOf(address(escrow)) <= 1);
        // assertTrue(erc20.balanceOf(address(escrow)) <= 1);

        // assertApproxEqAbs(erc20.balanceOf(self), (amount / 2), 1);
        // assertApproxEqAbs(erc20.balanceOf(investor), (amount / 2), 1);
        // assertTrue(lPool.maxWithdraw(self) <= 1);
        // assertTrue(lPool.maxRedeem(self) <= 1);

        // // withdrawing or redeeming more should revert
        // vm.expectRevert(bytes("InvestmentManager/exceeds-redeem-limits"));
        // lPool.withdraw(2, investor, self);
        // vm.expectRevert(bytes("InvestmentManager/exceeds-redeem-limits"));
        // lPool.redeem(2, investor, self);
    }
}
