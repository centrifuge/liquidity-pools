// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import "./TestSetup.t.sol";
import "src/LiquidityPool.sol";
import {MigratedInvestmentManager} from "test/migrationContracts/MigratedInvestmentManager.sol";
import {MathLib} from "src/util/MathLib.sol";

// import "forge-std/Test.sol";

contract MigrationsTest is TestSetup {
    using MathLib for uint128;

    uint8 internal constant PRICE_DECIMALS = 18;

    uint64 poolId;
    bytes16 trancheId;
    uint128 currencyId;
    uint8 trancheTokenDecimals;
    address _lPool;
    address investor;
    uint256 investorCurrencyAmount;

    function setUp() public override {
        super.setUp();
        investor = vm.addr(100);
        poolId = 1;
        trancheId = bytes16(hex"811acd5b3f17c06841c7e41e9e04cb1b");
        currencyId = 1;
        trancheTokenDecimals = 18;
        _lPool = deployLiquidityPool(poolId, trancheTokenDecimals, erc20.name(), erc20.symbol(), trancheId, currencyId, address(erc20));

        investorCurrencyAmount = 1000 * 10 ** erc20.decimals();
        deal(address(erc20), investor, investorCurrencyAmount);
        homePools.updateMember(poolId, trancheId, investor, uint64(block.timestamp + 1000 days));
    }

    function testInvestmentManagerMigration() public {
        // Make sure it works first
        InvestAndRedeem(poolId, trancheId, _lPool);
        // address[] memory investors = new address[](1);
        // investors[0] = investor;
        // address[] memory liquidityPools = new address[](1);
        // liquidityPools[0] = _lPool;
        // MigratedInvestmentManager newInvestmentManager = new MigratedInvestmentManager(address(escrow), address(userEscrow), address(investmentManager), investors, liquidityPools);
        
    }

    function testLiquidityPoolMigration() public {}

    function testRootMigration() public {}

    function testPoolManagerMigration() public {}


    // --- Investment and Redeem Flow ---

    function InvestAndRedeem(
        uint64 poolId,
        bytes16 trancheId,
        address _lPool
    ) public {
        uint128 price = uint128(2 * 10 ** PRICE_DECIMALS); //TODO: fuzz price
        LiquidityPool lPool = LiquidityPool(_lPool);

        depositMint(poolId, trancheId, price, investorCurrencyAmount, lPool);
        uint256 redeemAmount = lPool.balanceOf(investor);

        redeemWithdraw(
            poolId, trancheId, price, redeemAmount, lPool
        );
    }

    function depositMint(
        uint64 poolId,
        bytes16 trancheId,
        uint128 price,
        uint256 amount,
        LiquidityPool lPool
    ) public {
        vm.prank(investor);
        erc20.approve(address(investmentManager), amount); // add allowance
        vm.prank(investor);
        lPool.requestDeposit(amount, investor);

        // ensure funds are locked in escrow
        assertEq(erc20.balanceOf(address(escrow)), amount);
        assertEq(erc20.balanceOf(investor), 0);

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
            poolId, trancheId, investor, _currencyId, uint128(amount), trancheTokensPayout, 0
        );

        assertEq(lPool.maxMint(investor), trancheTokensPayout);
        assertEq(lPool.maxDeposit(investor), amount);
        assertEq(lPool.balanceOf(address(escrow)), trancheTokensPayout);
        assertEq(erc20.balanceOf(investor), 0);

        uint256 div = 2;
        vm.prank(investor);
        lPool.deposit(amount / div, investor);

        assertEq(lPool.balanceOf(investor), trancheTokensPayout / div);
        assertEq(lPool.balanceOf(address(escrow)), trancheTokensPayout - trancheTokensPayout / div);
        assertEq(lPool.maxMint(investor), trancheTokensPayout - trancheTokensPayout / div);
        assertEq(lPool.maxDeposit(investor), amount - amount / div); // max deposit

        console.log("trancheTokensPayout", trancheTokensPayout);
        console.log("lPool.maxDeposit", lPool.maxDeposit(investor));
        console.log("lPool.maxMint", lPool.maxMint(investor));
        console.log("lPool.balanceOf(address(escrow))", lPool.balanceOf(address(escrow)));
        console.log("erc20.balanceOf(investor)", erc20.balanceOf(investor));
        // console.log("deposit amount", amount / div);
        vm.prank(investor);
        lPool.mint(lPool.maxMint(investor), investor);

        assertEq(lPool.balanceOf(investor), trancheTokensPayout);
        assertTrue(lPool.balanceOf(address(escrow)) <= 1);
        assertTrue(lPool.maxMint(investor) <= 1);
    }

    function redeemWithdraw(
        uint64 poolId,
        bytes16 trancheId,
        uint128 price,
        uint256 amount,
        LiquidityPool lPool
    ) public {
        vm.expectRevert(bytes("ERC20/insufficient-allowance"));
        vm.prank(investor);
        lPool.requestRedeem(amount, investor);
        vm.prank(investor);
        lPool.approve(address(investmentManager), amount);
        vm.prank(investor);
        lPool.requestRedeem(amount, investor);

        // redeem
        uint128 _currencyId = poolManager.currencyAddressToId(address(erc20)); // retrieve currencyId
        uint128 currencyPayout = _toUint128(
            uint128(amount).mulDiv(price, 10 ** (18 - erc20.decimals() + lPool.decimals()), MathLib.Rounding.Down)
        );
        // Assume an epoch execution happens on cent chain
        // Assume a bot calls collectRedeem for this user on cent chain
        vm.prank(address(gateway));
        investmentManager.handleExecutedCollectRedeem(
            poolId, trancheId, investor, _currencyId, currencyPayout, uint128(amount), 0
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

        vm.prank(investor);
        lPool.withdraw(lPool.maxWithdraw(investor), investor, investor);
        assertEq(lPool.balanceOf(investor), 0);
        assertEq(lPool.balanceOf(address(escrow)), 0);
        assertEq(erc20.balanceOf(investor), currencyPayout);
        assertEq(lPool.maxWithdraw(investor), 0);
        assertEq(lPool.maxRedeem(investor), 0);
    }

    // --- Helpers ---

    function _toUint128(uint256 _value) internal pure returns (uint128 value) {
        if (_value > type(uint128).max) {
            revert("InvestmentManager/uint128-overflow");
        } else {
            value = uint128(_value);
        }
    }
}