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
import "forge-std/Test.sol";

interface ApproveLike {
    function approve(address, uint256) external;
}

contract DeployTest is Test {
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
        uint128 price = 1e27;
        uint128 currencyId = 1;
        uint256 amount = 1000;
        uint64 validUntil = uint64(block.timestamp + 1000 days);
        address lPool_ = deployPoolAndTranche(poolId, trancheId, tokenName, tokenSymbol, decimals, price);
        LiquidityPool lPool = LiquidityPool(lPool_);
        depositMint(poolId, decimals, tokenName, tokenSymbol, trancheId, price, currencyId, amount, validUntil, lPool);
        // time passes and price changes
        // vm.warp(block.timestamp + 500 days);
        // vm.prank(address(gateway));
        // price = price * 2;
        tokenManager.updateTrancheTokenPrice(poolId, trancheId, price);
        TrancheToken token = TrancheToken(investmentManager.getTrancheToken(poolId, trancheId));
        amount = token.balanceOf(self);
        redeem(poolId, decimals, tokenName, tokenSymbol, trancheId, price, currencyId, amount, validUntil, lPool);
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
        vm.assume(currencyId > 0);
        vm.assume(amount < type(uint128).max);
        vm.assume(amount > 1);
        vm.assume(validUntil >= block.timestamp);
        price = 2;

        deal(address(erc20), self, amount);

        // will fail - user not member: can not receive trancheToken
        vm.expectRevert(bytes("InvestmentManager/not-a-member"));
        lPool.requestDeposit(amount, self);
        vm.prank(address(gateway));
        tokenManager.updateMember(poolId, trancheId, self, validUntil); // add user as member
        delete validUntil;

        // // will fail - user did not give currency allowance to investmentManager
        vm.expectRevert(bytes("Dai/insufficient-allowance"));
        lPool.requestDeposit(amount, self);
        erc20.approve(address(investmentManager), amount); // add allowance

        lPool.requestDeposit(amount, self);

        // ensure funds are locked in escrow
        assertEq(erc20.balanceOf(address(escrow)), amount);
        assertEq(erc20.balanceOf(self), 0);

        // trigger executed collectInvest
        uint128 _currencyId = tokenManager.currencyAddressToId(address(erc20)); // retrieve currencyId
        uint128 trancheTokensPayout = uint128(amount) / price; // trancheTokenPrice = 2$
        vm.prank(address(gateway));
        investmentManager.handleExecutedCollectInvest(
            poolId, trancheId, self, _currencyId, uint128(amount), trancheTokensPayout
        );

        // assert deposit & mint values adjusted
        assertEq(lPool.maxMint(self), trancheTokensPayout); // max deposit
        assertEq(lPool.maxDeposit(self), amount); // max deposit
        // assert tranche tokens minted
        assertEq(lPool.balanceOf(address(escrow)), trancheTokensPayout);

        // deposit a share of the amount
        uint256 share = 2;
        lPool.deposit(amount / share, self); // mint hald the amount
        assertEq(lPool.balanceOf(self), trancheTokensPayout / share);
        assertEq(lPool.balanceOf(address(escrow)), trancheTokensPayout - trancheTokensPayout / share);
        assertEq(lPool.maxMint(self), trancheTokensPayout - trancheTokensPayout / share); // max deposit
        assertEq(lPool.maxDeposit(self), amount - amount / share); // max deposit

        // mint the rest
        lPool.mint(lPool.maxMint(self), self);
        assertEq(lPool.balanceOf(self), trancheTokensPayout - lPool.maxMint(self));
        assertTrue(lPool.balanceOf(address(escrow)) <= 1);
        assertTrue(lPool.maxMint(self) <= 1);
    }

    function redeem(
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
        deposit(address(lPool), poolId, trancheId, amount, validUntil); // deposit funds first

        lPool.approve(address(lPool), amount);
        lPool.requestRedeem(amount, self);

        // redeem
        uint128 _currencyId = tokenManager.currencyAddressToId(address(erc20)); // retrieve currencyId
        uint128 currencyPayout = uint128(amount) / price;
        vm.prank(address(gateway));
        investmentManager.handleExecutedCollectRedeem(
            poolId, trancheId, self, _currencyId, currencyPayout, uint128(amount)
        );

        // assert withdraw & redeem values adjusted
        assertEq(lPool.maxWithdraw(self), currencyPayout); // max deposit
        assertEq(lPool.maxRedeem(self), amount); // max deposit
        assertEq(lPool.balanceOf(address(escrow)), 0);

        lPool.redeem(amount, self, self); // mint hald the amount
        assertEq(lPool.balanceOf(self), 0);
        assertEq(lPool.balanceOf(address(escrow)), 0);
        assertEq(erc20.balanceOf(self), amount);
        assertEq(lPool.maxMint(self), 0);
        assertEq(lPool.maxDeposit(self), 0);
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

    function deposit(address _lPool, uint64 poolId, bytes16 trancheId, uint256 amount, uint64 validUntil) public {
        LiquidityPool lPool = LiquidityPool(_lPool);
        deal(address(erc20), self, amount);
        vm.prank(address(gateway));
        tokenManager.updateMember(poolId, trancheId, self, validUntil); // add user as member
        erc20.approve(address(investmentManager), amount); // add allowance
        lPool.requestDeposit(amount, self);
        // trigger executed collectInvest
        uint128 currencyId = tokenManager.currencyAddressToId(address(erc20)); // retrieve currencyId
        vm.prank(address(gateway));
        investmentManager.handleExecutedCollectInvest(
            poolId, trancheId, self, currencyId, uint128(amount), uint128(amount)
        );
        lPool.deposit(amount, self); // withdraw the amount
    }
}
