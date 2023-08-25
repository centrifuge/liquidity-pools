// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.18;
pragma abicoder v2;

import {InvestmentManager, Tranche} from "../src/InvestmentManager.sol";
import {TokenManager} from "../src/TokenManager.sol";
import {Gateway} from "../src/gateway/Gateway.sol";
import {Escrow} from "../src/Escrow.sol";
import {LiquidityPoolFactory, TrancheTokenFactory, MemberlistFactory} from "../src/util//Factory.sol";
import {LiquidityPool} from "../src/LiquidityPool.sol";
import {ERC20} from "../src/token/ERC20.sol";

import {MemberlistLike, Memberlist} from "../src/token/Memberlist.sol";
import {MockHomeLiquidityPools} from "./mock/MockHomeLiquidityPools.sol";
import {MockXcmRouter} from "./mock/MockXcmRouter.sol";
import {Messages} from "../src/gateway/Messages.sol";
import {PauseAdmin} from "../src/gateway/admins/PauseAdmin.sol";
import {DelayedAdmin} from "../src/gateway/admins/DelayedAdmin.sol";
import "forge-std/Test.sol";
import "../src/InvestmentManager.sol";

interface EscrowLike_ {
    function approve(address token, address spender, uint256 value) external;
    function rely(address usr) external;
}

interface AuthLike_ {
    function wards(address user) external returns (uint256);
}

contract LiquidityPoolTest is Test {
    uint128 constant MAX_UINT128 = type(uint128).max;

    InvestmentManager evmInvestmentManager;
    TokenManager evmTokenManager;
    Gateway gateway;
    MockHomeLiquidityPools homePools;
    MockXcmRouter mockXcmRouter;
    Escrow escrow;
    ERC20 erc20;

    function setUp() public {
        vm.chainId(1);
        uint256 shortWait = 24 hours;
        uint256 longWait = 48 hours;
        uint256 gracePeriod = 48 hours;
        escrow = new Escrow();
        erc20 = newErc20("X's Dollar", "USDX", 42);
        address liquidityPoolFactory_ = address(new LiquidityPoolFactory());
        address memberlistFactory_ = address(new MemberlistFactory());
        address trancheTokenFactory_ = address(new TrancheTokenFactory());

        evmInvestmentManager =
            new InvestmentManager(address(escrow), liquidityPoolFactory_, trancheTokenFactory_, memberlistFactory_);
        evmTokenManager = new TokenManager(address(escrow));

        mockXcmRouter = new MockXcmRouter(address(evmInvestmentManager));

        homePools = new MockHomeLiquidityPools(address(mockXcmRouter));
        PauseAdmin pauseAdmin = new PauseAdmin();
        DelayedAdmin delayedAdmin = new DelayedAdmin();

        gateway =
        new Gateway(address(evmInvestmentManager), address(evmTokenManager), address(mockXcmRouter), shortWait, longWait, gracePeriod);
        gateway.rely(address(pauseAdmin));
        gateway.rely(address(delayedAdmin));
        pauseAdmin.file("gateway", address(gateway));
        delayedAdmin.file("gateway", address(gateway));
        evmInvestmentManager.file("gateway", address(gateway));
        evmInvestmentManager.file("tokenManager", address(evmTokenManager));
        evmTokenManager.file("gateway", address(gateway));
        evmTokenManager.file("investmentManager", address(evmInvestmentManager));
        escrow.rely(address(evmInvestmentManager));
        escrow.rely(address(evmTokenManager));
        mockXcmRouter.file("gateway", address(gateway));
        evmInvestmentManager.rely(address(gateway));
        escrow.rely(address(gateway));
    }

    function testDepositMint(
        uint64 poolId,
        uint8 decimals,
        string memory tokenName,
        string memory tokenSymbol,
        bytes16 trancheId,
        uint128 price,
        uint128 currencyId,
        uint256 amount,
        uint64 validUntil
    ) public {
        vm.assume(currencyId > 0);
        vm.assume(amount < MAX_UINT128);
        vm.assume(amount > 1);
        vm.assume(validUntil >= block.timestamp);
        price = 2;

        address lPool_ = deployLiquidityPool(poolId, decimals, tokenName, tokenSymbol, trancheId, price, currencyId);
        LiquidityPool lPool = LiquidityPool(lPool_);

        erc20.mint(address(this), amount);

        // will fail - user not member: can not receive trancheToken
        vm.expectRevert(bytes("InvestmentManager/not-a-member"));
        lPool.requestDeposit(amount);
        homePools.updateMember(poolId, trancheId, address(this), validUntil); // add user as member

        // // will fail - user did not give currency allowance to investmentManager
        vm.expectRevert(bytes("ERC20/insufficient-allowance"));
        lPool.requestDeposit(amount);
        erc20.approve(address(evmInvestmentManager), amount); // add allowance

        lPool.requestDeposit(amount);

        // ensure funds are locked in escrow
        assertEq(erc20.balanceOf(address(escrow)), amount);
        assertEq(erc20.balanceOf(address(this)), 0);

        // trigger executed collectInvest
        uint128 _currencyId = evmTokenManager.currencyAddressToId(address(erc20)); // retrieve currencyId
        uint128 trancheTokensPayout = uint128(amount) / price; // trancheTokenPrice = 2$
        homePools.isExecutedCollectInvest(
            poolId, trancheId, bytes32(bytes20(address(this))), _currencyId, uint128(amount), trancheTokensPayout
        );

        // assert deposit & mint values adjusted
        assertEq(lPool.maxMint(address(this)), trancheTokensPayout); // max deposit
        assertEq(lPool.maxDeposit(address(this)), amount); // max deposit
        // assert tranche tokens minted
        assertEq(lPool.balanceOf(address(escrow)), trancheTokensPayout);

        // deposit a share of the amount
        uint256 share = 2;
        lPool.deposit(amount / share, address(this)); // mint hald the amount
        assertEq(lPool.balanceOf(address(this)), trancheTokensPayout / share);
        assertEq(lPool.balanceOf(address(escrow)), trancheTokensPayout - trancheTokensPayout / share);
        assertEq(lPool.maxMint(address(this)), trancheTokensPayout - trancheTokensPayout / share); // max deposit
        assertEq(lPool.maxDeposit(address(this)), amount - amount / share); // max deposit

        // mint the rest
        lPool.mint(lPool.maxMint(address(this)), address(this));
        assertEq(lPool.balanceOf(address(this)), trancheTokensPayout - lPool.maxMint(address(this)));
        assertTrue(lPool.balanceOf(address(escrow)) <= 1);
        assertTrue(lPool.maxMint(address(this)) <= 1);
        //assertTrue(lPool.maxDeposit(address(this)) <= 2); // todo: fix rounding
    }

    function testRedeem(
        uint64 poolId,
        uint8 decimals,
        string memory tokenName,
        string memory tokenSymbol,
        bytes16 trancheId,
        uint128 price,
        uint128 currencyId,
        uint256 amount,
        uint64 validUntil
    ) public {
        vm.assume(currencyId > 0);
        vm.assume(amount < MAX_UINT128);
        vm.assume(amount > 1);
        vm.assume(validUntil >= block.timestamp);
        price = 1;

        address lPool_ = deployLiquidityPool(poolId, decimals, tokenName, tokenSymbol, trancheId, price, currencyId);
        deposit(lPool_, poolId, trancheId, amount, validUntil); // deposit funds first
        LiquidityPool lPool = LiquidityPool(lPool_);

        // will fail - user did not give tranche token allowance to investmentManager
        vm.expectRevert(bytes("InvestmentManager/insufficient-balance"));
        lPool.requestDeposit(amount);
        lPool.approve(address(lPool), amount); // add allowance

        lPool.requestRedeem(amount);
        assertEq(lPool.balanceOf(address(escrow)), amount);

        // trigger executed collectRedeem
        uint128 _currencyId = evmTokenManager.currencyAddressToId(address(erc20)); // retrieve currencyId
        uint128 currencyPayout = uint128(amount) / price;
        homePools.isExecutedCollectRedeem(
            poolId, trancheId, bytes32(bytes20(address(this))), _currencyId, currencyPayout, uint128(amount)
        );

        // assert withdraw & redeem values adjusted
        assertEq(lPool.maxWithdraw(address(this)), currencyPayout); // max deposit
        assertEq(lPool.maxRedeem(address(this)), amount); // max deposit
        assertEq(lPool.balanceOf(address(escrow)), 0);

        console.logUint(lPool.maxRedeem(address(this)));
        console.logUint(amount);

        lPool.redeem(amount, address(this), address(this)); // mint hald the amount
        assertEq(lPool.balanceOf(address(this)), 0);
        assertEq(lPool.balanceOf(address(escrow)), 0);
        assertEq(erc20.balanceOf(address(this)), amount);
        assertEq(lPool.maxMint(address(this)), 0);
        assertEq(lPool.maxDeposit(address(this)), 0);
    }

    // helpers

    function testWithdraw(
        uint64 poolId,
        uint8 decimals,
        string memory tokenName,
        string memory tokenSymbol,
        bytes16 trancheId,
        uint128 price,
        uint128 currencyId,
        uint256 amount,
        uint64 validUntil
    ) public {
        vm.assume(currencyId > 0);
        vm.assume(amount < MAX_UINT128);
        vm.assume(amount > 1);
        vm.assume(validUntil >= block.timestamp);
        price = 1;

        address lPool_ = deployLiquidityPool(poolId, decimals, tokenName, tokenSymbol, trancheId, price, currencyId);
        deposit(lPool_, poolId, trancheId, amount, validUntil); // deposit funds first
        LiquidityPool lPool = LiquidityPool(lPool_);

        // will fail - user did not give tranche token allowance to investmentManager
        vm.expectRevert(bytes("InvestmentManager/insufficient-balance"));
        lPool.requestDeposit(amount);
        lPool.approve(address(lPool), amount); // add allowance

        lPool.requestRedeem(amount);
        assertEq(lPool.balanceOf(address(escrow)), amount);

        // trigger executed collectRedeem
        uint128 _currencyId = evmTokenManager.currencyAddressToId(address(erc20)); // retrieve currencyId
        uint128 currencyPayout = uint128(amount) / price;
        homePools.isExecutedCollectRedeem(
            poolId, trancheId, bytes32(bytes20(address(this))), _currencyId, currencyPayout, uint128(amount)
        );

        // assert withdraw & redeem values adjusted
        assertEq(lPool.maxWithdraw(address(this)), currencyPayout); // max deposit
        assertEq(lPool.maxRedeem(address(this)), amount); // max deposit
        assertEq(lPool.balanceOf(address(escrow)), 0);

        console.logUint(lPool.maxRedeem(address(this)));
        console.logUint(amount);

        lPool.withdraw(amount, address(this), address(this)); // mint hald the amount
        assertEq(lPool.balanceOf(address(this)), 0);
        assertEq(lPool.balanceOf(address(escrow)), 0);
        assertEq(erc20.balanceOf(address(this)), amount);
        assertEq(lPool.maxMint(address(this)), 0);
        assertEq(lPool.maxDeposit(address(this)), 0);
    }

    function testCollectInvest(
        uint64 poolId,
        bytes16 trancheId,
        string memory tokenName,
        string memory tokenSymbol,
        uint8 decimals,
        uint128 price,
        uint128 currency,
        uint64 validUntil,
        uint128 amount
    ) public {
        vm.assume(amount > 0);
        vm.assume(currency > 0);
        vm.assume(decimals > 0);
        vm.assume(validUntil > block.timestamp + 7 days);

        address lPool_ = deployLiquidityPool(poolId, decimals, tokenName, tokenSymbol, trancheId, price, currency);
        LiquidityPool lPool = LiquidityPool(lPool_);

        vm.expectRevert(bytes("InvestmentManager/not-a-member"));
        lPool.collectInvest(address(this));

        homePools.updateMember(poolId, trancheId, address(this), validUntil);
        lPool.collectInvest(address(this));
    }

    function testCollectRedeem(
        uint64 poolId,
        bytes16 trancheId,
        string memory tokenName,
        string memory tokenSymbol,
        uint8 decimals,
        uint128 price,
        uint128 currency,
        uint8 trancheDecimals,
        uint64 validUntil,
        uint128 amount
    ) public {
        vm.assume(amount > 0);
        vm.assume(currency > 0);
        vm.assume(trancheDecimals > 0);
        vm.assume(validUntil > block.timestamp + 7 days);

        address lPool_ = deployLiquidityPool(poolId, decimals, tokenName, tokenSymbol, trancheId, price, currency);
        LiquidityPool lPool = LiquidityPool(lPool_);
        homePools.allowPoolCurrency(poolId, currency);

        vm.expectRevert(bytes("InvestmentManager/not-a-member"));
        lPool.collectRedeem(address(this));
        homePools.updateMember(poolId, trancheId, address(this), validUntil);

        lPool.collectRedeem(address(this));
    }

    function deposit(address _lPool, uint64 poolId, bytes16 trancheId, uint256 amount, uint64 validUntil) public {
        LiquidityPool lPool = LiquidityPool(_lPool);
        erc20.mint(address(this), amount);
        homePools.updateMember(poolId, trancheId, address(this), validUntil); // add user as member
        erc20.approve(address(evmInvestmentManager), amount); // add allowance
        lPool.requestDeposit(amount);
        // trigger executed collectInvest
        uint128 currencyId = evmTokenManager.currencyAddressToId(address(erc20)); // retrieve currencyId
        homePools.isExecutedCollectInvest(
            poolId, trancheId, bytes32(bytes20(address(this))), currencyId, uint128(amount), uint128(amount)
        );
        lPool.deposit(amount, address(this)); // withdraw hald the amount
    }

    function deployLiquidityPool(
        uint64 poolId,
        uint8 decimals,
        string memory tokenName,
        string memory tokenSymbol,
        bytes16 trancheId,
        uint128 price,
        uint128 currency
    ) public returns (address) {
        homePools.addPool(poolId); // add pool
        homePools.addTranche(poolId, trancheId, tokenName, tokenSymbol, decimals, price); // add tranche
        homePools.addCurrency(currency, address(erc20));
        homePools.allowPoolCurrency(poolId, currency);
        evmInvestmentManager.deployTranche(poolId, trancheId);

        address lPoolAddress = evmInvestmentManager.deployLiquidityPool(poolId, trancheId, address(erc20));
        return lPoolAddress;
    }

    function newErc20(string memory name, string memory symbol, uint8 decimals) internal returns (ERC20) {
        ERC20 currency = new ERC20(decimals);
        currency.file("name", name);
        currency.file("symbol", symbol);
        return currency;
    }
}
