// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.18;
pragma abicoder v2;

import {InvestmentManager, Tranche} from "../src/InvestmentManager.sol";
import {TokenManager} from "../src/TokenManager.sol";
import {Gateway} from "../src/gateway/Gateway.sol";
import {Root} from "../src/Root.sol";
import {Escrow} from "../src/Escrow.sol";
import {LiquidityPoolFactory, TrancheTokenFactory} from "../src/util//Factory.sol";
import {LiquidityPool, TrancheTokenLike} from "../src/LiquidityPool.sol";
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

interface TrancheToken {
    function isTrustedForwarder(address forwarder) external view  returns (bool);
    function addTrustedForwarder(address forwarder) external;
    function removeTrustedForwarder(address forwarder) external;
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
        erc20 = newErc20("X's Dollar", "USDX", 6);
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
        vm.assume(amount > 4);
        vm.assume(validUntil >= block.timestamp);
        price = 1;
        Investor investor = new Investor();

        address lPool_ =
            deployLiquidityPool(poolId, erc20.decimals(), tokenName, tokenSymbol, trancheId, price, currencyId);
        investorDeposit(address(investor), lPool_, poolId, trancheId, amount, validUntil); // deposit funds first
        LiquidityPool lPool = LiquidityPool(lPool_);
        homePools.updateMember(poolId, trancheId, self, validUntil); // put self on memberlist to be able to receive tranche tokens

        TrancheToken trancheToken = TrancheToken(address(lPool.share()));
        assert(trancheToken.isTrustedForwarder(lPool_) == true); // Lpool is not trusted forwarder on token
    
        uint initBalance = lPool.balanceOf(address(investor));
        uint transferAmount = amount / 4;
    
        // replacing msg sender only possible for trusted forwarder
        assert(trancheToken.isTrustedForwarder(self) == false); // Lpool is not trusted forwarder on token
        (bool success, bytes memory data) = address(trancheToken).call(abi.encodeWithSelector(bytes4(keccak256(bytes("transferFrom(address,address,uint256)"))), address(investor), self, transferAmount, address(investor)));
        assertEq(success, false);

        // remove LiquidityPool as trusted forwarder
        root.relyContract(address(trancheToken), self);
        trancheToken.removeTrustedForwarder(lPool_);
        assert(trancheToken.isTrustedForwarder(lPool_) == false); // adding trusted forwarder works

        vm.expectRevert(bytes("ERC20/insufficient-allowance")); 
        investor.transferFrom(lPool_, address(investor), self, transferAmount);

        // add liquidityPool back as trusted forwarder
        trancheToken.addTrustedForwarder(lPool_);

        investor.transferFrom(lPool_, address(investor), self, transferAmount);
        assert(lPool.balanceOf(address(investor)) == (initBalance - transferAmount));
        assert(lPool.balanceOf(self) == transferAmount);
    }

       function testApprove(
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
        LiquidityPool lPool = LiquidityPool(lPool_);
        
        TrancheToken trancheToken = TrancheToken(address(lPool.share()));
        assert(trancheToken.isTrustedForwarder(lPool_) == true); // Lpool is not trusted forwarder on token
    
        uint initBalance = lPool.balanceOf(address(investor));
        uint approvalAmount = amount / 4;

        Investor random = new Investor();
    
        // replacing msg sender only possible for trusted forwarder
        assert(trancheToken.isTrustedForwarder(self) == false); // Lpool is not trusted forwarder on token
        (bool success, bytes memory data) = address(trancheToken).call(abi.encodeWithSelector(bytes4(keccak256(bytes("approve(address,uint256)"))), address(random), approvalAmount, address(investor)));
        assertEq(lPool.allowance(self, address(random)), approvalAmount);
        assertEq(lPool.allowance(address(investor), address(random)), 0);


        // remove LiquidityPool as trusted forwarder
        root.relyContract(address(trancheToken), self);
        trancheToken.removeTrustedForwarder(lPool_);
        assert(trancheToken.isTrustedForwarder(lPool_) == false); // adding trusted forwarder works

        investor.approve(lPool_, address(random), approvalAmount);
        assertEq(lPool.allowance(lPool_, address(random)), approvalAmount);
        assertEq(lPool.allowance(address(investor), address(random)), 0);

        // add liquidityPool back as trusted forwarder
        trancheToken.addTrustedForwarder(lPool_);

        investor.approve(lPool_, address(random), approvalAmount);
        assertEq(lPool.allowance(address(investor), address(random)), approvalAmount);
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

        address lPool_ =
            deployLiquidityPool(poolId, erc20.decimals(), tokenName, tokenSymbol, trancheId, price, currencyId);
        investorDeposit(address(investor), lPool_, poolId, trancheId, amount, validUntil); // deposit funds first
        LiquidityPool lPool = LiquidityPool(lPool_);
        homePools.updateMember(poolId, trancheId, self, validUntil); // put self on memberlist to be able to receive tranche tokens

        TrancheToken trancheToken = TrancheToken(address(lPool.share()));
        assert(trancheToken.isTrustedForwarder(lPool_) == true); // Lpool is not trusted forwarder on token
    
        uint initBalance = lPool.balanceOf(address(investor));
        uint transferAmount = amount / 4;

        // replacing msg sender only possible for trusted forwarder
        assert(trancheToken.isTrustedForwarder(self) == false); // Lpool is not trusted forwarder on token
        (bool success, bytes memory data) = address(trancheToken).call(abi.encodeWithSelector(bytes4(keccak256(bytes("transfer(address,uint256)"))), self, transferAmount, address(investor)));
        assertEq(success, false);

        // remove LiquidityPool as trusted forwarder
        root.relyContract(address(trancheToken), self);
        trancheToken.removeTrustedForwarder(lPool_);
        assert(trancheToken.isTrustedForwarder(lPool_) == false); // adding trusted forwarder works

        vm.expectRevert(bytes("ERC20/insufficient-balance")); 
        investor.transfer(lPool_, self, transferAmount);

        // add liquidityPool back as trusted forwarder
        trancheToken.addTrustedForwarder(lPool_);
        investor.transfer(lPool_, self, transferAmount);

        // investor.transfer(lPool_, self, transferAmount);
        assert(lPool.balanceOf(address(investor)) == (initBalance - transferAmount));
        assert(lPool.balanceOf(self) == transferAmount);
    }

    function testDepositAndRedeemPrecision(uint64 poolId, bytes16 trancheId, uint128 currencyId) public {
        vm.assume(currencyId > 0);

        uint8 TRANCHE_TOKEN_DECIMALS = 18; // Like DAI
        uint8 INVESTMENT_CURRENCY_DECIMALS = 6; // 6, like USDC
        uint8 PRICE_DECIMALS = 27; // Prices are always 27 decimals

        address lPool_ = deployLiquidityPool(
            poolId, TRANCHE_TOKEN_DECIMALS, "", "", trancheId, 1000000000000000000000000000, currencyId
        );
        LiquidityPool lPool = LiquidityPool(lPool_);

        // invest
        uint256 investmentAmount = 100000000; // 100 * 10**6
        homePools.updateMember(poolId, trancheId, self, type(uint64).max);
        erc20.approve(address(evmInvestmentManager), investmentAmount);
        erc20.mint(self, investmentAmount);
        lPool.requestDeposit(investmentAmount, self);

        // trigger executed collectInvest of the first 50% at a price of 1.2
        uint128 _currencyId = evmTokenManager.currencyAddressToId(address(erc20)); // retrieve currencyId
        uint128 currencyPayout = 50000000; // 50 * 10**6
        uint128 firstTrancheTokenPayout = 41666666666666666666; // 50 * 10**18 / 1.2, rounded down
        homePools.isExecutedCollectInvest(
            poolId, trancheId, bytes32(bytes20(self)), _currencyId, currencyPayout, firstTrancheTokenPayout
        );

        // assert deposit & mint values adjusted
        assertEq(lPool.maxDeposit(self), currencyPayout);
        assertEq(lPool.maxMint(self), firstTrancheTokenPayout);

        // deposit price should be ~1.2*10**27. max precision possible is limited by 18 decimals of the tranche tokens
        assertEq(evmInvestmentManager.calculateDepositPrice(self, address(lPool)), 1200000000000000000019200000);

        // trigger executed collectInvest of the second 50% at a price of 1.4
        currencyPayout = 50000000; // 50 * 10**6
        uint128 secondTrancheTokenPayout = 35714285714285714285; // 50 * 10**18 / 1.4, rounded down
        homePools.isExecutedCollectInvest(
            poolId, trancheId, bytes32(bytes20(self)), _currencyId, currencyPayout, secondTrancheTokenPayout
        );

        // deposit price should now be 50% * 1.2 + 50% * 1.4 = ~1.3*10**27.
        assertEq(evmInvestmentManager.calculateDepositPrice(self, address(lPool)), 1292307692307692307715370414);

        // collect the tranche tokens
        lPool.mint(firstTrancheTokenPayout + secondTrancheTokenPayout, self);
        assertEq(lPool.balanceOf(self), firstTrancheTokenPayout + secondTrancheTokenPayout);

        // redeem
        lPool.approve(address(evmInvestmentManager), firstTrancheTokenPayout + secondTrancheTokenPayout);
        lPool.requestRedeem(firstTrancheTokenPayout + secondTrancheTokenPayout, self);

        // trigger executed collectRedeem at a price of 1.5
        // 50% invested at 1.2 and 50% invested at 1.4 leads to ~77 tranche tokens
        // when redeeming at a price of 1.5, this leads to ~115.5 currency
        currencyPayout = 115500000; // 115.5*10**6

        // mint interest into escrow
        erc20.mint(address(escrow), currencyPayout - investmentAmount);

        homePools.isExecutedCollectRedeem(
            poolId,
            trancheId,
            bytes32(bytes20(self)),
            _currencyId,
            currencyPayout,
            firstTrancheTokenPayout + secondTrancheTokenPayout
        );

        // redeem price should now be ~1.5*10**27.
        assertEq(evmInvestmentManager.calculateRedeemPrice(self, address(lPool)), 1492615384615384615411252828);

        // collect the currency
        lPool.withdraw(currencyPayout, self, self);
        assertEq(erc20.balanceOf(self), currencyPayout);
    }

    function testAssetShareConversion(uint64 poolId, bytes16 trancheId, uint128 currencyId) public {
        vm.assume(currencyId > 0);

        uint8 TRANCHE_TOKEN_DECIMALS = 18; // Like DAI
        uint8 INVESTMENT_CURRENCY_DECIMALS = 6; // 6, like USDC
        uint8 PRICE_DECIMALS = 27; // Prices are always 27 decimals

        address lPool_ = deployLiquidityPool(
            poolId, TRANCHE_TOKEN_DECIMALS, "", "", trancheId, 1000000000000000000000000000, currencyId
        );
        LiquidityPool lPool = LiquidityPool(lPool_);

        // invest
        uint256 investmentAmount = 100000000; // 100 * 10**6
        homePools.updateMember(poolId, trancheId, self, type(uint64).max);
        erc20.approve(address(evmInvestmentManager), investmentAmount);
        erc20.mint(self, investmentAmount);
        lPool.requestDeposit(investmentAmount, self);

        // trigger executed collectInvest at a price of 1.0
        uint128 _currencyId = evmTokenManager.currencyAddressToId(address(erc20)); // retrieve currencyId
        uint128 trancheTokenPayout = 100000000000000000000; // 100 * 10**18
        homePools.isExecutedCollectInvest(
            poolId, trancheId, bytes32(bytes20(self)), _currencyId, uint128(investmentAmount), trancheTokenPayout
        );
        lPool.mint(trancheTokenPayout, self);

        // assert share/asset conversion
        assertEq(lPool.latestPrice(), 1000000000000000000000000000);
        assertEq(lPool.totalAssets(), 100000000000000000000);
        assertEq(lPool.convertToShares(100000000000000000000), 100000000000000000000);
        assertEq(lPool.convertToAssets(lPool.convertToShares(100000000000000000000)), 100000000000000000000);

        // assert share/asset conversion after price update
        homePools.updateTrancheTokenPrice(poolId, trancheId, 1200000000000000000000000000);

        assertEq(lPool.latestPrice(), 1200000000000000000000000000);
        assertEq(lPool.totalAssets(), 120000000000000000000);
        assertEq(lPool.convertToShares(120000000000000000000), 100000000000000000000);
        assertEq(lPool.convertToAssets(lPool.convertToShares(120000000000000000000)), 120000000000000000000);
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
        price = 2 * 10 ** 27;

        address lPool_ =
            deployLiquidityPool(poolId, erc20.decimals(), tokenName, tokenSymbol, trancheId, price, currencyId);
        LiquidityPool lPool = LiquidityPool(lPool_);

        erc20.mint(self, amount);

        // will fail - user not member: can not receive trancheToken
        vm.expectRevert(bytes("InvestmentManager/not-a-member"));
        lPool.requestDeposit(amount, self);
        homePools.updateMember(poolId, trancheId, self, validUntil); // add user as member

        // // will fail - user did not give currency allowance to investmentManager
        vm.expectRevert(bytes("ERC20/insufficient-allowance"));
        lPool.requestDeposit(amount, self);
        erc20.approve(address(evmInvestmentManager), amount); // add allowance

        lPool.requestDeposit(amount, self);

        // ensure funds are locked in escrow
        assertEq(erc20.balanceOf(address(escrow)), amount);
        assertEq(erc20.balanceOf(self), 0);

        // trigger executed collectInvest
        uint128 _currencyId = evmTokenManager.currencyAddressToId(address(erc20)); // retrieve currencyId
        uint128 trancheTokensPayout = uint128(amount * 10 ** 27 / price); // trancheTokenPrice = 2$
        assertApproxEqAbs(trancheTokensPayout, amount / 2, 1);
        homePools.isExecutedCollectInvest(
            poolId, trancheId, bytes32(bytes20(self)), _currencyId, uint128(amount), trancheTokensPayout
        );

        // assert deposit & mint values adjusted
        assertEq(lPool.maxMint(self), trancheTokensPayout); // max deposit
        assertEq(lPool.maxDeposit(self), amount); // max deposit
        // assert tranche tokens minted
        assertEq(lPool.balanceOf(address(escrow)), trancheTokensPayout);

        // deposit 50% of the amount
        uint256 share = 2;
        lPool.deposit(amount / 2, self); // mint half the amount

        // Allow 1 difference because of rounding
        assertApproxEqAbs(lPool.balanceOf(self), trancheTokensPayout / 2, 1);
        assertApproxEqAbs(lPool.balanceOf(address(escrow)), trancheTokensPayout - trancheTokensPayout / 2, 1);
        assertApproxEqAbs(lPool.maxMint(self), trancheTokensPayout - trancheTokensPayout / 2, 1);
        assertApproxEqAbs(lPool.maxDeposit(self), amount - amount / 2, 1);

        // mint the rest
        lPool.mint(lPool.maxMint(self), self);
        assertEq(lPool.balanceOf(self), trancheTokensPayout - lPool.maxMint(self));
        assertTrue(lPool.balanceOf(address(escrow)) <= 1);
        assertTrue(lPool.maxMint(self) <= 1);

        // remainder is rounding difference
        assertTrue(lPool.maxDeposit(address(this)) <= amount * 0.01e18);
    }

    function testDepositAndRedeemWithPermit(
        uint64 poolId,
        string memory tokenName,
        string memory tokenSymbol,
        bytes16 trancheId,
        uint128 currencyId,
        uint256 amount
    ) public {
        vm.assume(currencyId > 0);
        vm.assume(amount < MAX_UINT128);
        vm.assume(amount > 1);

        // Use a wallet with a known private key so we can sign the permit message
        address investor = vm.addr(0xABCD);
        vm.prank(vm.addr(0xABCD));

        LiquidityPool lPool = LiquidityPool(
            deployLiquidityPool(poolId, erc20.decimals(), tokenName, tokenSymbol, trancheId, 1, currencyId)
        );
        erc20.mint(investor, amount);
        homePools.updateMember(poolId, trancheId, investor, type(uint64).max);

        // Sign permit for depositing investment currency
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            0xABCD,
            keccak256(
                abi.encodePacked(
                    "\x19\x01",
                    erc20.DOMAIN_SEPARATOR(),
                    keccak256(
                        abi.encode(
                            erc20.PERMIT_TYPEHASH(), investor, address(evmInvestmentManager), amount, 0, block.timestamp
                        )
                    )
                )
            )
        );

        lPool.requestDepositWithPermit(amount, investor, block.timestamp, v, r, s);
        // To avoid stack too deep errors
        delete v;
        delete r;
        delete s;

        // ensure funds are locked in escrow
        assertEq(erc20.balanceOf(address(escrow)), amount);
        assertEq(erc20.balanceOf(investor), 0);

        // collect 50% of the tranche tokens
        homePools.isExecutedCollectInvest(
            poolId,
            trancheId,
            bytes32(bytes20(investor)),
            evmTokenManager.currencyAddressToId(address(erc20)),
            uint128(amount),
            uint128(amount)
        );

        uint256 maxMint = lPool.maxMint(investor);
        lPool.mint(maxMint, investor);
        TrancheTokenLike trancheToken = lPool.share();
        assertEq(trancheToken.balanceOf(address(investor)), maxMint);
        
        // Sign permit for redeeming tranche tokens
        (v, r, s) = vm.sign(
            0xABCD,
            keccak256(
                abi.encodePacked(
                    "\x19\x01",
                    trancheToken.DOMAIN_SEPARATOR(),
                    keccak256(
                        abi.encode(
                            trancheToken.PERMIT_TYPEHASH(), investor, address(evmInvestmentManager), maxMint, 0, block.timestamp
                        )
                    )
                )
            )
        );
       
        lPool.requestRedeemWithPermit(maxMint, investor, block.timestamp, v, r, s);
        // ensure tokens are locked in escrow
        assertEq(trancheToken.balanceOf(address(escrow)), maxMint);
        assertEq(trancheToken.balanceOf(investor), 0);
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

        address lPool_ =
            deployLiquidityPool(poolId, erc20.decimals(), tokenName, tokenSymbol, trancheId, price, currencyId);
        deposit(lPool_, poolId, trancheId, amount, validUntil); // deposit funds first
        LiquidityPool lPool = LiquidityPool(lPool_);

        // will fail - user did not give tranche token allowance to investmentManager
        vm.expectRevert(bytes("ERC20/insufficient-allowance"));
        lPool.requestRedeem(amount, self);
        lPool.approve(address(evmInvestmentManager), amount); // add allowance

        lPool.requestRedeem(amount, self);
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

        address lPool_ =
            deployLiquidityPool(poolId, erc20.decimals(), tokenName, tokenSymbol, trancheId, price, currencyId);
        deposit(lPool_, poolId, trancheId, amount, validUntil); // deposit funds first
        LiquidityPool lPool = LiquidityPool(lPool_);

        // will fail - user did not give tranche token allowance to investmentManager
        vm.expectRevert(bytes("InvestmentManager/insufficient-balance"));
        lPool.requestDeposit(amount, self);
        lPool.approve(address(evmInvestmentManager), amount); // add allowance

        lPool.requestRedeem(amount, self);
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
        lPool.requestDeposit(amount, self);
        // trigger executed collectInvest
        uint128 currencyId = evmTokenManager.currencyAddressToId(address(erc20)); // retrieve currencyId
        homePools.isExecutedCollectInvest(
            poolId, trancheId, bytes32(bytes20(self)), currencyId, uint128(amount), uint128(amount)
        );
        lPool.deposit(amount, self); // withdraw the amount
    }

    function investorDeposit(
        address _investor,
        address _lPool,
        uint64 poolId,
        bytes16 trancheId,
        uint256 amount,
        uint64 validUntil
    ) public {
        Investor investor = Investor(_investor);
        LiquidityPool lPool = LiquidityPool(_lPool);
        erc20.mint(_investor, amount);
        homePools.updateMember(poolId, trancheId, _investor, validUntil); // add user as member
        investor.approve(address(erc20), address(evmInvestmentManager), amount); // add allowance
        investor.requestDeposit(_lPool, amount, _investor);
        uint128 currencyId = evmTokenManager.currencyAddressToId(address(erc20)); // retrieve currencyId
        homePools.isExecutedCollectInvest(
            poolId, trancheId, bytes32(bytes20(_investor)), currencyId, uint128(amount), uint128(amount)
        );
        investor.deposit(_lPool, amount, _investor); // withdraw the amount
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
