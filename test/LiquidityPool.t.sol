// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.18;
pragma abicoder v2;

import {InvestmentManager, Tranche} from "../src/InvestmentManager.sol";
import {TokenManager} from "../src/TokenManager.sol";
import {Gateway} from "../src/gateway/Gateway.sol";
import {Root} from "../src/Root.sol";
import {Escrow} from "../src/Escrow.sol";
import {LiquidityPoolFactory, TrancheTokenFactory} from "../src/util//Factory.sol";
import {LiquidityPool} from "../src/LiquidityPool.sol";
import {ERC20} from "../src/token/ERC20.sol";

import {MemberlistLike, Memberlist} from "../src/token/Memberlist.sol";
import {MockHomeLiquidityPools} from "./mock/MockHomeLiquidityPools.sol";
import {MockXcmRouter} from "./mock/MockXcmRouter.sol";
import {Messages} from "../src/gateway/Messages.sol";
import {Investor} from "./accounts/Investor.sol";
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

    Root root;
    InvestmentManager evmInvestmentManager;
    TokenManager evmTokenManager;
    Gateway gateway;
    MockHomeLiquidityPools homePools;
    MockXcmRouter mockXcmRouter;
    Escrow escrow;
    ERC20 erc20;

    address self;

    function setUp() public {
        vm.chainId(1);
        escrow = new Escrow();
        root = new Root(address(escrow), 48 hours);
        erc20 = newErc20("X's Dollar", "USDX", 42);
        LiquidityPoolFactory liquidityPoolFactory_ = new LiquidityPoolFactory(address(root));
        TrancheTokenFactory trancheTokenFactory_ = new TrancheTokenFactory(address(root));

        evmInvestmentManager =
            new InvestmentManager(address(escrow), address(liquidityPoolFactory_), address(trancheTokenFactory_));
        liquidityPoolFactory_.rely(address(evmInvestmentManager));
        trancheTokenFactory_.rely(address(evmInvestmentManager));
        evmTokenManager = new TokenManager(address(escrow));

        mockXcmRouter = new MockXcmRouter(address(evmInvestmentManager));

        homePools = new MockHomeLiquidityPools(address(mockXcmRouter));

        gateway =
            new Gateway(address(root), address(evmInvestmentManager), address(evmTokenManager), address(mockXcmRouter));
        evmInvestmentManager.file("gateway", address(gateway));
        evmInvestmentManager.file("tokenManager", address(evmTokenManager));
        evmTokenManager.file("gateway", address(gateway));
        evmTokenManager.file("investmentManager", address(evmInvestmentManager));
        escrow.rely(address(evmInvestmentManager));
        escrow.rely(address(evmTokenManager));
        mockXcmRouter.file("gateway", address(gateway));
        evmInvestmentManager.rely(address(gateway));
        escrow.rely(address(gateway));

        self = address(this);

    }

    function testTransferFrom(
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
        vm.assume(amount > 100);
        vm.assume(validUntil >= block.timestamp);
        price = 1;
        Investor investor = new Investor();

        
        address lPool_ = deployLiquidityPool(poolId, decimals, tokenName, tokenSymbol, trancheId, price, currencyId);
        investorDeposit(address(investor), lPool_, poolId, trancheId, amount, validUntil); // deposit funds first
        LiquidityPool lPool = LiquidityPool(lPool_);
        homePools.updateMember(poolId, trancheId, self, validUntil); // put self on memberlist to be able to receive tranche tokens

        // investor fails to transfer tranche tokens no approval on LPool
        vm.expectRevert(bytes("ERC20/insufficient-allowance")); // Todo -> discuss to add auto-approval on transfer
        investor.transferFrom(lPool_, address(investor), self, amount / 4);

        // investor can transfer tranche tokens
        investor.approve(lPool_, lPool_, type(uint256).max); 
        investor.transferFrom(lPool_, address(investor), self, amount / 4);

        // Random user (self) can not transfer tokens on behalf of user
        vm.expectRevert(bytes("LiquidityPool/no-token-allowance"));
        lPool.transferFrom(address(investor), self, amount / 4);

        // Random user (self) can transfer tokens on behalf of user after approval granted 
        investor.approve(lPool_, self, amount / 4); 
        lPool.transferFrom(address(investor), self, amount / 4);
    }

    function testTransfer(
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
        vm.assume(amount > 100);
        vm.assume(validUntil >= block.timestamp);
        price = 1;
        Investor investor = new Investor();

        
        address lPool_ = deployLiquidityPool(poolId, decimals, tokenName, tokenSymbol, trancheId, price, currencyId);
        investorDeposit(address(investor), lPool_, poolId, trancheId, amount, validUntil); // deposit funds first
        LiquidityPool lPool = LiquidityPool(lPool_);
        homePools.updateMember(poolId, trancheId, self, validUntil); // put self on memberlist to be able to receive tranche tokens

        // investor fails to transfer tranche tokens no approval on LPool
        vm.expectRevert(bytes("ERC20/insufficient-allowance")); // Todo -> discuss to add auto-approval on transfer
        investor.transfer(lPool_, self, amount / 4);

        // investor can transfer tranche tokens
        investor.approve(lPool_, lPool_, type(uint256).max); 
        investor.transfer(lPool_, self, amount / 4);
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

        erc20.mint(self, amount);

        // will fail - user not member: can not receive trancheToken
        vm.expectRevert(bytes("InvestmentManager/not-a-member"));
        lPool.requestDeposit(self, amount);
        homePools.updateMember(poolId, trancheId, self, validUntil); // add user as member

        // // will fail - user did not give currency allowance to investmentManager
        vm.expectRevert(bytes("ERC20/insufficient-allowance"));
        lPool.requestDeposit(self, amount);
        erc20.approve(address(evmInvestmentManager), amount); // add allowance

        lPool.requestDeposit(self, amount);

        // ensure funds are locked in escrow
        assertEq(erc20.balanceOf(address(escrow)), amount);
        assertEq(erc20.balanceOf(self), 0);

        // trigger executed collectInvest
        uint128 _currencyId = evmTokenManager.currencyAddressToId(address(erc20)); // retrieve currencyId
        uint128 trancheTokensPayout = uint128(amount) / price; // trancheTokenPrice = 2$
        homePools.isExecutedCollectInvest(
            poolId, trancheId, bytes32(bytes20(self)), _currencyId, uint128(amount), trancheTokensPayout
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
        vm.expectRevert(bytes("ERC20/insufficient-allowance"));
        lPool.requestRedeem(self, amount);
        lPool.approve(address(lPool), amount); // add allowance

        lPool.requestRedeem(self, amount);
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
        lPool.requestDeposit(self, amount);
        lPool.approve(address(lPool), amount); // add allowance

        lPool.requestRedeem(self, amount);
        assertEq(lPool.balanceOf(address(escrow)), amount);

        // trigger executed collectRedeem
        uint128 _currencyId = evmTokenManager.currencyAddressToId(address(erc20)); // retrieve currencyId
        uint128 currencyPayout = uint128(amount) / price;
        homePools.isExecutedCollectRedeem(
            poolId, trancheId, bytes32(bytes20(self)), _currencyId, currencyPayout, uint128(amount)
        );

        // assert withdraw & redeem values adjusted
        assertEq(lPool.maxWithdraw(self), currencyPayout); // max deposit
        assertEq(lPool.maxRedeem(self), amount); // max deposit
        assertEq(lPool.balanceOf(address(escrow)), 0);

        console.logUint(lPool.maxRedeem(self));
        console.logUint(amount);

        lPool.withdraw(amount, self, self); // mint hald the amount
        assertEq(lPool.balanceOf(self), 0);
        assertEq(lPool.balanceOf(address(escrow)), 0);
        assertEq(erc20.balanceOf(self), amount);
        assertEq(lPool.maxMint(self), 0);
        assertEq(lPool.maxDeposit(self), 0);
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


    // helpers
    function deposit(address _lPool, uint64 poolId, bytes16 trancheId, uint256 amount, uint64 validUntil) public {
        LiquidityPool lPool = LiquidityPool(_lPool);
        erc20.mint(self, amount);
        homePools.updateMember(poolId, trancheId, self, validUntil); // add user as member
        erc20.approve(address(evmInvestmentManager), amount); // add allowance
        lPool.requestDeposit(self, amount);
        // trigger executed collectInvest
        uint128 currencyId = evmTokenManager.currencyAddressToId(address(erc20)); // retrieve currencyId
        homePools.isExecutedCollectInvest(
            poolId, trancheId, bytes32(bytes20(self)), currencyId, uint128(amount), uint128(amount)
        );
        lPool.deposit(amount, self); // withdraw hald the amount
    }

    function investorDeposit(address _investor, address _lPool, uint64 poolId, bytes16 trancheId, uint256 amount, uint64 validUntil) public {
        Investor investor = Investor(_investor);
        LiquidityPool lPool = LiquidityPool(_lPool);
        erc20.mint(_investor, amount);
        homePools.updateMember(poolId, trancheId, _investor, validUntil); // add user as member
        investor.approve(address(erc20), address(evmInvestmentManager), amount); // add allowance
        investor.requestDeposit(_lPool, _investor, amount);
        uint128 currencyId = evmTokenManager.currencyAddressToId(address(erc20)); // retrieve currencyId
        homePools.isExecutedCollectInvest(
            poolId, trancheId, bytes32(bytes20(_investor)), currencyId, uint128(amount), uint128(amount)
        );
        investor.deposit(_lPool, amount, _investor); // withdraw hald the amount
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
