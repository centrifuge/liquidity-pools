// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import "../TestSetup.t.sol";
import {LiquidityPool} from "src/LiquidityPool.sol";
import {MathLib} from "src/util/MathLib.sol";

contract InvestRedeemFlow is TestSetup {
    using MathLib for uint256;

    uint8 internal constant PRICE_DECIMALS = 18;

    uint64 poolId;
    bytes16 trancheId;
    uint128 currencyId;
    uint8 trancheTokenDecimals;
    address _lPool;
    uint256 investorCurrencyAmount;

    function setUp() public virtual override {
        super.setUp();
        poolId = 1;
        trancheId = bytes16(hex"811acd5b3f17c06841c7e41e9e04cb1b");
        currencyId = 1;
        trancheTokenDecimals = 18;
        _lPool = deployLiquidityPool(
            poolId, trancheTokenDecimals, erc20.name(), erc20.symbol(), trancheId, currencyId, address(erc20)
        );

        investorCurrencyAmount = 1000 * 10 ** erc20.decimals();
        deal(address(erc20), investor, investorCurrencyAmount);
        centrifugeChain.updateMember(poolId, trancheId, investor, uint64(block.timestamp + 1000 days));
        removeDeployerAccess(address(router), address(this));
    }

    function verifyInvestAndRedeemFlow(uint64 poolId_, bytes16 trancheId_, address liquidityPool) public {
        uint128 price = uint128(2 * 10 ** PRICE_DECIMALS);
        LiquidityPool lPool = LiquidityPool(liquidityPool);

        depositMint(poolId_, trancheId_, price, investorCurrencyAmount, lPool);
        uint256 redeemAmount = lPool.balanceOf(investor);

        redeemWithdraw(poolId_, trancheId_, price, redeemAmount, lPool);
    }

    function depositMint(uint64 poolId_, bytes16 trancheId_, uint128 price, uint256 currencyAmount, LiquidityPool lPool)
        public
    {
        vm.prank(investor);
        erc20.approve(address(lPool), currencyAmount); // add allowance

        vm.prank(investor);
        lPool.requestDeposit(currencyAmount, investor);

        // ensure funds are locked in escrow
        assertEq(erc20.balanceOf(address(escrow)), currencyAmount);
        assertEq(erc20.balanceOf(investor), investorCurrencyAmount - currencyAmount);

        // Assume an epoch execution happens on cent chain
        // Assume a bot calls collectInvest for this user on cent chain
        uint128 _currencyId = poolManager.currencyAddressToId(address(erc20));
        uint128 trancheTokensPayout = currencyAmount.mulDiv(
            10 ** (PRICE_DECIMALS - erc20.decimals() + lPool.decimals()), price, MathLib.Rounding.Down
        ).toUint128();
        vm.prank(address(gateway));
        investmentManager.handleExecutedCollectInvest(
            poolId_, trancheId_, investor, _currencyId, uint128(currencyAmount), trancheTokensPayout, 0
        );

        assertEq(lPool.maxMint(investor), trancheTokensPayout);
        assertEq(lPool.balanceOf(address(escrow)), trancheTokensPayout);
        assertEq(erc20.balanceOf(investor), investorCurrencyAmount - currencyAmount);

        uint256 div = 2;
        vm.prank(investor);
        lPool.deposit(currencyAmount / div, investor);

        assertEq(lPool.balanceOf(investor), trancheTokensPayout / div);
        assertEq(lPool.balanceOf(address(escrow)), trancheTokensPayout - trancheTokensPayout / div);
        assertEq(lPool.maxMint(investor), trancheTokensPayout - trancheTokensPayout / div);

        uint256 maxMint = lPool.maxMint(investor);
        vm.prank(investor);
        lPool.mint(maxMint, investor);

        assertEq(lPool.balanceOf(investor), trancheTokensPayout);
        assertLe(lPool.balanceOf(address(escrow)), 1);
        assertLe(lPool.maxMint(investor), 1);
    }

    function redeemWithdraw(uint64 poolId_, bytes16 trancheId_, uint128 price, uint256 tokenAmount, LiquidityPool lPool)
        public
    {
        vm.prank(investor);
        lPool.requestRedeem(tokenAmount, investor, investor);

        // Assume an epoch execution happens on cent chain
        // Assume a bot calls collectRedeem for this user on cent chain
        uint128 _currencyId = poolManager.currencyAddressToId(address(erc20)); // retrieve currencyId
        uint128 currencyPayout = tokenAmount.mulDiv(
            price, 10 ** (18 - erc20.decimals() + lPool.decimals()), MathLib.Rounding.Down
        ).toUint128();
        vm.prank(address(gateway));
        investmentManager.handleExecutedCollectRedeem(
            poolId_, trancheId_, investor, _currencyId, currencyPayout, uint128(tokenAmount), 0
        );

        assertEq(lPool.maxWithdraw(investor), currencyPayout);
        assertEq(lPool.maxRedeem(investor), tokenAmount);
        assertEq(lPool.balanceOf(address(escrow)), 0);

        uint128 div = 2;
        vm.prank(investor);
        lPool.redeem(tokenAmount / div, investor, investor);
        assertEq(lPool.balanceOf(investor), 0);
        assertEq(lPool.balanceOf(address(escrow)), 0);
        assertEq(erc20.balanceOf(investor), currencyPayout / div);
        assertEq(lPool.maxWithdraw(investor), currencyPayout / div);
        assertEq(lPool.maxRedeem(investor), tokenAmount / div);

        uint256 maxWithdraw = lPool.maxWithdraw(investor);
        vm.prank(investor);
        lPool.withdraw(maxWithdraw, investor, investor);
        assertEq(lPool.balanceOf(investor), 0);
        assertEq(lPool.balanceOf(address(escrow)), 0);
        assertEq(erc20.balanceOf(investor), currencyPayout);
        assertEq(lPool.maxWithdraw(investor), 0);
        assertEq(lPool.maxRedeem(investor), 0);
    }
}
