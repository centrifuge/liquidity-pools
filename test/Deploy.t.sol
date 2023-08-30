// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.18;
pragma abicoder v2;

import {InvestmentManager, Pool, Tranche} from "src/InvestmentManager.sol";
import {Gateway, RouterLike} from "src/gateway/Gateway.sol";
import {MockHomeLiquidityPools} from "test/mock/MockHomeLiquidityPools.sol";
import {Escrow} from "src/Escrow.sol";
import {PauseAdmin} from "src/admins/PauseAdmin.sol";
import {DelayedAdmin} from "src/admins/DelayedAdmin.sol";
import {MockXcmRouter} from "test/mock/MockXcmRouter.sol";
import {TokenManager} from "src/TokenManager.sol";
import {ERC20} from "src/token/ERC20.sol";
import {TrancheToken} from "src/token/Tranche.sol";
import {LiquidityPoolTest} from "test/LiquidityPool.t.sol";
import {PermissionlessRouter} from "test/mock/PermissionlessRouter.sol";
import {Root} from "src/Root.sol";
import {LiquidityPool} from "src/LiquidityPool.sol";

import {AxelarEVMScript} from "script/AxelarEVM.s.sol";
import {PermissionlessScript} from "script/Permissionless.s.sol";
import "src/util/Math.sol";
import "forge-std/Test.sol";

interface ApproveLike {
    function approve(address, uint256) external;
}

contract DeployTest is Test {
    using Math for uint128;

    InvestmentManager investmentManager;
    Gateway gateway;
    Root root;
    MockHomeLiquidityPools mockLiquidityPools;
    RouterLike router;
    Escrow escrow;
    PauseAdmin pauseAdmin;
    DelayedAdmin delayedAdmin;
    TokenManager tokenManager;

    address self;
    ERC20 erc20;

    function setUp() public {
        PermissionlessScript script = new PermissionlessScript();
        script.run();

        investmentManager = script.investmentManager();
        gateway = script.gateway();
        root = script.root();
        escrow = script.escrow();
        pauseAdmin = script.pauseAdmin();
        delayedAdmin = script.delayedAdmin();
        tokenManager = script.tokenManager();

        erc20 = ERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F); //Mainnet Dai
        self = address(this);
    }

    function testDeployAndInvestRedeem(
        uint64 poolId,
        uint8 decimals,
        string memory tokenName,
        string memory tokenSymbol,
        bytes16 trancheId
    ) public {
        uint8 decimals = 6;
        uint128 price = uint128(2 * 10 ** 27);
        uint128 currencyId = 1;
        uint256 amount = 1000 * 10 ** erc20.decimals();
        uint64 validUntil = uint64(block.timestamp + 1000 days);
        address lPool_ = deployPoolAndTranche(poolId, trancheId, tokenName, tokenSymbol, decimals, price);
        LiquidityPool lPool = LiquidityPool(lPool_);

        deal(address(erc20), self, amount);

        vm.prank(address(gateway));
        tokenManager.updateMember(poolId, trancheId, self, validUntil);

        depositMint(poolId, decimals, tokenName, tokenSymbol, trancheId, price, currencyId, amount, validUntil, lPool);
        amount = lPool.balanceOf(self);

        redeemWithdraw(
            poolId, decimals, tokenName, tokenSymbol, trancheId, price, currencyId, amount, validUntil, lPool
        );
    }

    function depositMint(
        uint64 poolId,
        uint8 decimals,
        string memory tokenName,
        string memory tokenSymbol,
        bytes16 trancheId,
        uint128 price,
        uint128 currencyId,
        uint256 amount,
        uint64 validUntil,
        LiquidityPool lPool
    ) public {
        erc20.approve(address(investmentManager), amount); // add allowance
        lPool.requestDeposit(amount, self);

        // ensure funds are locked in escrow
        assertEq(erc20.balanceOf(address(escrow)), amount);
        assertEq(erc20.balanceOf(self), 0);

        // trigger executed collectInvest
        uint128 _currencyId = tokenManager.currencyAddressToId(address(erc20)); // retrieve currencyId

        uint128 trancheTokensPayout = _toUint128(
            uint128(amount).mulDiv(10 ** (27 - erc20.decimals() + lPool.decimals()), price, Math.Rounding.Down)
        );

        // Assume an epoch execution happens on cent chain
        // Assume a bot calls collectInvest for this user on cent chain

        vm.prank(address(gateway));
        investmentManager.handleExecutedCollectInvest(
            poolId, trancheId, self, _currencyId, uint128(amount), trancheTokensPayout
        );

        assertEq(lPool.maxMint(self), trancheTokensPayout);
        assertEq(lPool.maxDeposit(self), amount);
        assertEq(lPool.balanceOf(address(escrow)), trancheTokensPayout);
        assertEq(erc20.balanceOf(self), 0);

        uint256 div = 2;
        lPool.deposit(amount / div, self);

        assertEq(lPool.balanceOf(self), trancheTokensPayout / div);
        assertEq(lPool.balanceOf(address(escrow)), trancheTokensPayout - trancheTokensPayout / div);
        assertEq(lPool.maxMint(self), trancheTokensPayout - trancheTokensPayout / div);
        assertEq(lPool.maxDeposit(self), amount - amount / div); // max deposit

        lPool.mint(lPool.maxMint(self), self);

        assertEq(lPool.balanceOf(self), trancheTokensPayout);
        assertTrue(lPool.balanceOf(address(escrow)) <= 1);
        assertTrue(lPool.maxMint(self) <= 1);
    }

    function redeemWithdraw(
        uint64 poolId,
        uint8 decimals,
        string memory tokenName,
        string memory tokenSymbol,
        bytes16 trancheId,
        uint128 price,
        uint128 currencyId,
        uint256 amount,
        uint64 validUntil,
        LiquidityPool lPool
    ) public {
        lPool.approve(address(lPool), amount);
        lPool.requestRedeem(amount, self);

        // redeem
        uint128 _currencyId = tokenManager.currencyAddressToId(address(erc20)); // retrieve currencyId
        uint128 currencyPayout = _toUint128(
            uint128(amount).mulDiv(price, 10 ** (27 - erc20.decimals() + lPool.decimals()), Math.Rounding.Down)
        );
        // Assume an epoch execution happens on cent chain
        // Assume a bot calls collectRedeem for this user on cent chain
        vm.prank(address(gateway));
        investmentManager.handleExecutedCollectRedeem(
            poolId, trancheId, self, _currencyId, currencyPayout, uint128(amount)
        );

        assertEq(lPool.maxWithdraw(self), currencyPayout);
        assertEq(lPool.maxRedeem(self), amount);
        assertEq(lPool.balanceOf(address(escrow)), 0);

        uint128 div = 2;
        lPool.redeem(amount / div, self, self);
        assertEq(lPool.balanceOf(self), 0);
        assertEq(lPool.balanceOf(address(escrow)), 0);
        assertEq(erc20.balanceOf(self), currencyPayout / div);
        assertEq(lPool.maxWithdraw(self), currencyPayout / div);
        assertEq(lPool.maxRedeem(self), amount / div);

        lPool.withdraw(lPool.maxWithdraw(self), self, self);
        assertEq(lPool.balanceOf(self), 0);
        assertEq(lPool.balanceOf(address(escrow)), 0);
        assertEq(erc20.balanceOf(self), currencyPayout);
        assertEq(lPool.maxWithdraw(self), 0);
        assertEq(lPool.maxRedeem(self), 0);
    }

    // helpers

    function deployPoolAndTranche(
        uint64 poolId,
        bytes16 trancheId,
        string memory tokenName,
        string memory tokenSymbol,
        uint8 decimals,
        uint128 price
    ) public returns (address) {
        uint64 validUntil = uint64(block.timestamp + 1000 days);

        vm.startPrank(address(gateway));
        investmentManager.addPool(poolId);
        investmentManager.addTranche(poolId, trancheId, tokenName, tokenSymbol, decimals, price);
        tokenManager.addCurrency(1, address(erc20));
        investmentManager.allowPoolCurrency(poolId, 1);
        vm.stopPrank();

        investmentManager.deployTranche(poolId, trancheId);
        address lPool = investmentManager.deployLiquidityPool(poolId, trancheId, address(erc20));
        return lPool;
    }

    function _toUint128(uint256 _value) internal pure returns (uint128 value) {
        if (_value > type(uint128).max) {
            revert();
        } else {
            value = uint128(_value);
        }
    }
}
