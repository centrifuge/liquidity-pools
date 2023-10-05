// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import "../TestSetup.t.sol";
import {LiquidityPool} from "src/LiquidityPool.sol";
import {MathLib} from "src/util/MathLib.sol";

interface AuthLike {
    function rely(address) external;
    function deny(address) external;
}

contract InvestRedeemFlow is TestSetup {
    using MathLib for uint128;

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

    function VerifyInvestAndRedeemFlow(uint64 poolId_, bytes16 trancheId_, address liquidityPool) public {
        uint128 price = uint128(2 * 10 ** PRICE_DECIMALS); //TODO: fuzz price
        LiquidityPool lPool = LiquidityPool(liquidityPool);

        depositMint(poolId_, trancheId_, price, investorCurrencyAmount, lPool);
        uint256 redeemAmount = lPool.balanceOf(investor);

        redeemWithdraw(poolId_, trancheId_, price, redeemAmount, lPool);
    }

    function depositMint(uint64 poolId_, bytes16 trancheId_, uint128 price, uint256 amount, LiquidityPool lPool)
        public
    {
        vm.prank(investor);
        erc20.approve(address(investmentManager), amount); // add allowance

        vm.prank(investor);
        lPool.requestDeposit(amount);

        // ensure funds are locked in escrow
        assertEq(erc20.balanceOf(address(escrow)), amount);
        assertEq(erc20.balanceOf(investor), investorCurrencyAmount - amount);

        // trigger executed collectInvest
        uint128 _currencyId = poolManager.currencyAddressToId(address(erc20)); // retrieve currencyId

        uint128 trancheTokensPayout = _toUint128(
            uint128(amount).mulDiv(
                10 ** (PRICE_DECIMALS - erc20.decimals() + lPool.decimals()), price, MathLib.Rounding.Down
            )
        );

        // Assume an epoch execution happens on cent chain
        // Assume a bot calls collectInvest for this user on cent chain
        vm.prank(address(gateway));
        investmentManager.handleExecutedCollectInvest(
            poolId_, trancheId_, investor, _currencyId, uint128(amount), trancheTokensPayout, 0
        );

        assertEq(lPool.maxMint(investor), trancheTokensPayout);
        assertEq(lPool.balanceOf(address(escrow)), trancheTokensPayout);
        assertEq(erc20.balanceOf(investor), investorCurrencyAmount - amount);

        uint256 div = 2;
        vm.prank(investor);
        lPool.deposit(amount / div, investor);

        assertEq(lPool.balanceOf(investor), trancheTokensPayout / div);
        assertEq(lPool.balanceOf(address(escrow)), trancheTokensPayout - trancheTokensPayout / div);
        assertEq(lPool.maxMint(investor), trancheTokensPayout - trancheTokensPayout / div);

        uint256 maxMint = lPool.maxMint(investor);
        vm.prank(investor);
        lPool.mint(maxMint, investor);

        assertEq(lPool.balanceOf(investor), trancheTokensPayout);
        assertTrue(lPool.balanceOf(address(escrow)) <= 1);
        assertTrue(lPool.maxMint(investor) <= 1);
    }

    function redeemWithdraw(uint64 poolId_, bytes16 trancheId_, uint128 price, uint256 amount, LiquidityPool lPool)
        public
    {
        vm.prank(investor);
        lPool.requestRedeem(amount);

        // redeem
        uint128 _currencyId = poolManager.currencyAddressToId(address(erc20)); // retrieve currencyId
        uint128 currencyPayout = _toUint128(
            uint128(amount).mulDiv(price, 10 ** (18 - erc20.decimals() + lPool.decimals()), MathLib.Rounding.Down)
        );
        // Assume an epoch execution happens on cent chain
        // Assume a bot calls collectRedeem for this user on cent chain
        vm.prank(address(gateway));
        investmentManager.handleExecutedCollectRedeem(
            poolId_, trancheId_, investor, _currencyId, currencyPayout, uint128(amount), 0
        );

        assertEq(lPool.maxWithdraw(investor), currencyPayout);
        assertEq(lPool.maxRedeem(investor), amount);
        assertEq(lPool.balanceOf(address(escrow)), 0);

        uint128 div = 2;
        vm.prank(investor);
        lPool.redeem(amount / div, investor, investor);
        assertEq(lPool.balanceOf(investor), 0);
        assertEq(lPool.balanceOf(address(escrow)), 0);
        assertEq(erc20.balanceOf(investor), currencyPayout / div);
        assertEq(lPool.maxWithdraw(investor), currencyPayout / div);
        assertEq(lPool.maxRedeem(investor), amount / div);

        uint256 maxWithdraw = lPool.maxWithdraw(investor);
        vm.prank(investor);
        lPool.withdraw(maxWithdraw, investor, investor);
        assertEq(lPool.balanceOf(investor), 0);
        assertEq(lPool.balanceOf(address(escrow)), 0);
        assertEq(erc20.balanceOf(investor), currencyPayout);
        assertEq(lPool.maxWithdraw(investor), 0);
        assertEq(lPool.maxRedeem(investor), 0);
    }

    // --- Utils ---

    function _toUint128(uint256 _value) internal pure returns (uint128 value) {
        if (_value > type(uint128).max) {
            revert("InvestmentManager/uint128-overflow");
        } else {
            value = uint128(_value);
        }
    }
}
