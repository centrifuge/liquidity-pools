// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import "./TestSetup.t.sol";

contract LiquidityPoolTest is TestSetup {
    // Deployment
    function testDeployment(
        uint64 poolId,
        string memory tokenName,
        string memory tokenSymbol,
        bytes16 trancheId,
        uint128 currencyId
    ) public {
        vm.assume(currencyId > 0);

        address lPool_ = deployLiquidityPool(poolId, erc20.decimals(), tokenName, tokenSymbol, trancheId, currencyId);
        LiquidityPool lPool = LiquidityPool(lPool_);

        // values set correctly
        assertEq(address(lPool.investmentManager()), address(investmentManager));
        assertEq(lPool.asset(), address(erc20));
        assertEq(lPool.poolId(), poolId);
        assertEq(lPool.trancheId(), trancheId);
        address token = poolManager.getTrancheToken(poolId, trancheId);
        assertEq(address(lPool.share()), token);
        assertEq(_bytes128ToString(_stringToBytes128(tokenName)), _bytes128ToString(_stringToBytes128(lPool.name())));
        assertEq(_bytes32ToString(_stringToBytes32(tokenSymbol)), _bytes32ToString(_stringToBytes32(lPool.symbol())));

        // permissions set correctly
        assertEq(lPool.wards(address(root)), 1);
        // assertEq(investmentManager.wards(self), 0); // deployer has no permissions
    }

    // --- Administration ---
    function testFile(
        uint64 poolId,
        string memory tokenName,
        string memory tokenSymbol,
        bytes16 trancheId,
        uint128 currencyId
    ) public {
        vm.assume(currencyId > 0);
        address lPool_ = deployLiquidityPool(poolId, erc20.decimals(), tokenName, tokenSymbol, trancheId, currencyId);
        LiquidityPool lPool = LiquidityPool(lPool_);

        vm.expectRevert(bytes("Auth/not-authorized"));
        lPool.file("investmentManager", self);

        root.relyContract(lPool_, self);
        lPool.file("investmentManager", self);

        vm.expectRevert(bytes("LiquidityPool/file-unrecognized-param"));
        lPool.file("random", self);
    }

    // --- Permissioned functions ---
    function testDepositWithApproval(
        uint64 poolId,
        uint8 decimals,
        string memory tokenName,
        string memory tokenSymbol,
        bytes16 trancheId,
        uint128 currencyId,
        uint256 amount,
        uint64 validUntil
    ) public {
        vm.assume(currencyId > 0);
        vm.assume(amount < MAX_UINT128);
        vm.assume(amount > 1);
        vm.assume(validUntil >= block.timestamp);

        address lPool_ = deployLiquidityPool(poolId, erc20.decimals(), tokenName, tokenSymbol, trancheId, currencyId);
        LiquidityPool lPool = LiquidityPool(lPool_);
        Investor investor = new Investor();
        erc20.mint(address(investor), type(uint256).max);
        investor.approve(address(erc20), address(investmentManager), type(uint256).max); // add allowance
        homePools.updateMember(poolId, trancheId, address(investor), validUntil); // add user as member

        // fail: no approval
        vm.expectRevert(bytes("LiquidityPool/no-approval"));
        lPool.requestDeposit(amount, address(investor));

        // investor gives approval to self
        investor.approve(address(erc20), self, amount);
        // fail: even if investor grants approval to self
        vm.expectRevert(bytes("LiquidityPool/no-approval"));
        lPool.requestDeposit(amount, address(investor));

        root.relyContract(lPool_, self);
        // success - ward can requestDeposit on behalf of investor
        lPool.requestDeposit(amount / 2, address(investor));
        lPool.deny(self); // revoke auth

        // success - investor can requestDeposit
        investor.requestDeposit(lPool_, amount / 2, address(investor));
    }

    // --- uint128 type checks ---
    // Make sure all function calls would fail when overflow uint128
    function testAssertUint128(
        uint64 poolId,
        uint8 decimals,
        string memory tokenName,
        string memory tokenSymbol,
        bytes16 trancheId,
        uint128 currencyId,
        uint256 amount,
        address random
    ) public {
        vm.assume(currencyId > 0);
        vm.assume(amount > MAX_UINT128); // amount has to overfloe UINT128
        address lPool_ = deployLiquidityPool(poolId, erc20.decimals(), tokenName, tokenSymbol, trancheId, currencyId);
        LiquidityPool lPool = LiquidityPool(lPool_);

        vm.expectRevert(bytes("InvestmentManager/uint128-overflow"));
        lPool.convertToShares(amount);

        vm.expectRevert(bytes("InvestmentManager/uint128-overflow"));
        lPool.convertToAssets(amount);

        vm.expectRevert(bytes("InvestmentManager/uint128-overflow"));
        lPool.previewDeposit(amount);

        vm.expectRevert(bytes("InvestmentManager/uint128-overflow"));
        lPool.previewRedeem(amount);

        vm.expectRevert(bytes("InvestmentManager/uint128-overflow"));
        lPool.previewMint(amount);

        vm.expectRevert(bytes("InvestmentManager/uint128-overflow"));
        lPool.previewWithdraw(amount);

        vm.expectRevert(bytes("InvestmentManager/uint128-overflow"));
        lPool.deposit(amount, random);

        vm.expectRevert(bytes("InvestmentManager/uint128-overflow"));
        lPool.mint(amount, random);

        vm.expectRevert(bytes("InvestmentManager/uint128-overflow"));
        lPool.withdraw(amount, random, self);

        vm.expectRevert(bytes("InvestmentManager/uint128-overflow"));
        lPool.redeem(amount, random, self);

        vm.expectRevert(bytes("InvestmentManager/uint128-overflow"));
        lPool.requestDeposit(amount, self);

        vm.expectRevert(bytes("InvestmentManager/uint128-overflow"));
        lPool.requestRedeem(amount, self);

        vm.expectRevert(bytes("InvestmentManager/uint128-overflow"));
        lPool.decreaseDepositRequest(amount, self);

        vm.expectRevert(bytes("InvestmentManager/uint128-overflow"));
        lPool.decreaseRedeemRequest(amount, self);
    }

    function testRedeemWithApproval(
        uint64 poolId,
        uint8 decimals,
        string memory tokenName,
        string memory tokenSymbol,
        bytes16 trancheId,
        uint128 currencyId,
        uint256 amount,
        uint64 validUntil
    ) public {
        vm.assume(currencyId > 0);
        vm.assume(amount < MAX_UINT128);
        vm.assume(amount > 4);
        vm.assume(validUntil >= block.timestamp);
        address lPool_ = deployLiquidityPool(poolId, erc20.decimals(), tokenName, tokenSymbol, trancheId, currencyId);
        LiquidityPool lPool = LiquidityPool(lPool_);
        Investor investor = new Investor();

        investorDeposit(address(investor), lPool_, poolId, trancheId, amount, validUntil); // deposit funds first
        investor.approve(lPool_, address(investmentManager), type(uint256).max);

        // fail: self can not claim for investor
        vm.expectRevert(bytes("LiquidityPool/no-approval"));
        lPool.requestRedeem(amount, address(investor));

        // investor gives approval to self
        investor.approve(lPool_, self, amount);

        // fail: even if investor grants approval to self
        vm.expectRevert(bytes("LiquidityPool/no-approval"));
        lPool.requestRedeem(amount, address(investor));

        // success - investor can requestRedeem
        investor.requestRedeem(lPool_, amount / 2, address(investor));

        root.relyContract(lPool_, self);
        // ward can requestRedeem on behalf of investor
        lPool.requestRedeem(amount / 2, address(investor));
        lPool.deny(self); // revoke auth

        uint128 tokenAmount = uint128(lPool.balanceOf(address(escrow)));
        homePools.isExecutedCollectRedeem(
            poolId, trancheId, bytes32(bytes20(address(investor))), currencyId, uint128(amount), uint128(tokenAmount)
        );

        assertEq(lPool.maxRedeem(address(investor)), tokenAmount);
        assertEq(lPool.maxWithdraw(address(investor)), uint128(amount));

        // test for both scenarios redeem & withdraw

        // fail: self cannot redeem for investor
        vm.expectRevert(bytes("LiquidityPool/no-approval"));
        lPool.redeem(amount / 4, address(investor), address(investor));
        vm.expectRevert(bytes("LiquidityPool/no-approval"));
        lPool.withdraw(amount / 4, address(investor), address(investor));

        // success redeem on behalf of investor with auth permissions
        root.relyContract(lPool_, self);
        lPool.redeem(amount / 4, address(investor), address(investor));
        lPool.withdraw(amount / 4, address(investor), address(investor));

        // investor redeems rest for himself
        investor.redeem(lPool_, amount / 4, address(investor), address(investor));
        investor.withdraw(lPool_, lPool.maxWithdraw(address(investor)), address(investor), address(investor));
    }

    function testMint(
        uint64 poolId,
        string memory tokenName,
        string memory tokenSymbol,
        bytes16 trancheId,
        uint128 currencyId,
        uint256 amount,
        uint64 validUntil
    ) public {
        vm.assume(currencyId > 0);
        vm.assume(amount < MAX_UINT128);
        vm.assume(validUntil >= block.timestamp);

        address lPool_ = deployLiquidityPool(poolId, erc20.decimals(), tokenName, tokenSymbol, trancheId, currencyId);
        LiquidityPool lPool = LiquidityPool(lPool_);

        Investor investor = new Investor();

        vm.expectRevert(bytes("Auth/not-authorized"));
        lPool.mint(address(investor), amount);

        root.relyContract(lPool_, self); // give self auth permissions

        vm.expectRevert(bytes("RestrictionManager/destination-not-a-member"));
        lPool.mint(address(investor), amount);

        homePools.updateMember(poolId, trancheId, address(investor), validUntil); // add investor as member

        lPool.mint(address(investor), amount);
        assertEq(lPool.balanceOf(address(investor)), amount);
        assertEq(lPool.balanceOf(address(investor)), lPool.share().balanceOf(address(investor)));
    }

    function testBurn(
        uint64 poolId,
        string memory tokenName,
        string memory tokenSymbol,
        bytes16 trancheId,
        uint128 currencyId,
        uint256 amount,
        uint64 validUntil
    ) public {
        vm.assume(currencyId > 0);
        vm.assume(amount < MAX_UINT128);
        vm.assume(amount > 0);
        vm.assume(validUntil >= block.timestamp);

        address lPool_ = deployLiquidityPool(poolId, erc20.decimals(), tokenName, tokenSymbol, trancheId, currencyId);
        LiquidityPool lPool = LiquidityPool(lPool_);

        Investor investor = new Investor();
        root.relyContract(lPool_, self); // give self auth permissions
        homePools.updateMember(poolId, trancheId, address(investor), validUntil); // add investor as member

        lPool.mint(address(investor), amount);
        root.denyContract(lPool_, self); // remove auth permissions from self

        vm.expectRevert(bytes("Auth/not-authorized"));
        lPool.burn(address(investor), amount);

        root.relyContract(lPool_, self); // give self auth permissions
        vm.expectRevert(bytes("ERC20/insufficient-allowance"));
        lPool.burn(address(investor), amount);

        // success
        investor.approve(lPool_, lPool_, amount); // approve LP to burn tokens
        lPool.burn(address(investor), amount);

        assertEq(lPool.balanceOf(address(investor)), 0);
        assertEq(lPool.balanceOf(address(investor)), lPool.share().balanceOf(address(investor)));
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

        address lPool_ = deployLiquidityPool(poolId, erc20.decimals(), tokenName, tokenSymbol, trancheId, currencyId);
        investorDeposit(address(investor), lPool_, poolId, trancheId, amount, validUntil); // deposit funds first
        LiquidityPool lPool = LiquidityPool(lPool_);
        homePools.updateMember(poolId, trancheId, self, validUntil); // put self on memberlist to be able to receive tranche tokens
        homePools.updateTrancheTokenPrice(poolId, trancheId, currencyId, price);

        TrancheToken trancheToken = TrancheToken(address(lPool.share()));
        assertEq(trancheToken.isTrustedForwarder(lPool_), true); // Lpool is trusted forwarder on token

        uint256 initBalance = lPool.balanceOf(address(investor));
        uint256 transferAmount = amount / 4;

        // replacing msg sender only possible for trusted forwarder
        assertEq(trancheToken.isTrustedForwarder(self), false); // self is not trusted forwarder on token
        (bool success, bytes memory data) = address(trancheToken).call(
            abi.encodeWithSelector(
                bytes4(keccak256(bytes("transferFrom(address,address,uint256)"))),
                address(investor),
                self,
                transferAmount,
                address(investor)
            )
        );
        assertEq(success, false);

        // remove LiquidityPool as trusted forwarder
        root.relyContract(address(trancheToken), self);
        trancheToken.removeLiquidityPool(lPool_);
        assertEq(trancheToken.isTrustedForwarder(lPool_), false); // adding trusted forwarder works

        vm.expectRevert(bytes("ERC20/insufficient-allowance"));
        investor.transferFrom(lPool_, address(investor), self, transferAmount);

        // add liquidityPool back as trusted forwarder
        trancheToken.addLiquidityPool(lPool_);

        investor.transferFrom(lPool_, address(investor), self, transferAmount);
        assertEq(lPool.balanceOf(address(investor)), (initBalance - transferAmount));
        assertEq(lPool.balanceOf(self), transferAmount);
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

        address lPool_ = deployLiquidityPool(poolId, decimals, tokenName, tokenSymbol, trancheId, currencyId);
        LiquidityPool lPool = LiquidityPool(lPool_);
        homePools.updateTrancheTokenPrice(poolId, trancheId, currencyId, price);

        TrancheToken trancheToken = TrancheToken(address(lPool.share()));
        assertTrue(trancheToken.isTrustedForwarder(lPool_)); // Lpool is not trusted forwarder on token

        uint256 initBalance = lPool.balanceOf(address(investor));
        uint256 approvalAmount = amount / 4;

        Investor random = new Investor();

        // replacing msg sender only possible for trusted forwarder
        assertEq(trancheToken.isTrustedForwarder(self), false); // Lpool is not trusted forwarder on token
        (bool success, bytes memory data) = address(trancheToken).call(
            abi.encodeWithSelector(
                bytes4(keccak256(bytes("approve(address,uint256)"))), address(random), approvalAmount, address(investor)
            )
        );
        assertEq(lPool.allowance(self, address(random)), approvalAmount);
        assertEq(lPool.allowance(address(investor), address(random)), 0);

        // remove LiquidityPool as trusted forwarder
        root.relyContract(address(trancheToken), self);
        trancheToken.removeLiquidityPool(lPool_);
        assertEq(trancheToken.isTrustedForwarder(lPool_), false); // adding trusted forwarder works

        investor.approve(lPool_, address(random), approvalAmount);
        assertEq(lPool.allowance(lPool_, address(random)), approvalAmount);
        assertEq(lPool.allowance(address(investor), address(random)), 0);

        // add liquidityPool back as trusted forwarder
        trancheToken.addLiquidityPool(lPool_);

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
        Investor investor = new Investor();

        address lPool_ = deployLiquidityPool(poolId, erc20.decimals(), tokenName, tokenSymbol, trancheId, currencyId);
        investorDeposit(address(investor), lPool_, poolId, trancheId, amount, validUntil); // deposit funds first
        LiquidityPool lPool = LiquidityPool(lPool_);
        homePools.updateMember(poolId, trancheId, self, validUntil); // put self on memberlist to be able to receive tranche tokens

        TrancheToken trancheToken = TrancheToken(address(lPool.share()));
        assertTrue(trancheToken.isTrustedForwarder(lPool_)); // Lpool is not trusted forwarder on token

        uint256 initBalance = lPool.balanceOf(address(investor));
        uint256 transferAmount = amount / 4;

        // replacing msg sender only possible for trusted forwarder
        assertEq(trancheToken.isTrustedForwarder(self), false); // Lpool is not trusted forwarder on token
        (bool success, bytes memory data) = address(trancheToken).call(
            abi.encodeWithSelector(
                bytes4(keccak256(bytes("transfer(address,uint256)"))), self, transferAmount, address(investor)
            )
        );
        assertEq(success, false);

        // remove LiquidityPool as trusted forwarder
        root.relyContract(address(trancheToken), self);
        trancheToken.removeLiquidityPool(lPool_);
        assertEq(trancheToken.isTrustedForwarder(lPool_), false); // adding trusted forwarder works

        vm.expectRevert(bytes("ERC20/insufficient-balance"));
        investor.transfer(lPool_, self, transferAmount);

        // add liquidityPool back as trusted forwarder
        trancheToken.addLiquidityPool(lPool_);
        investor.transfer(lPool_, self, transferAmount);

        // investor.transfer(lPool_, self, transferAmount);
        assertEq(lPool.balanceOf(address(investor)), (initBalance - transferAmount));
        assertEq(lPool.balanceOf(self), transferAmount);
    }

    function testDepositAndRedeemPrecision(uint64 poolId, bytes16 trancheId, uint128 currencyId) public {
        vm.assume(currencyId > 0);

        uint8 TRANCHE_TOKEN_DECIMALS = 18; // Like DAI
        uint8 INVESTMENT_CURRENCY_DECIMALS = 6; // 6, like USDC

        ERC20 currency = _newErc20("Currency", "CR", INVESTMENT_CURRENCY_DECIMALS);
        address lPool_ =
            deployLiquidityPool(poolId, TRANCHE_TOKEN_DECIMALS, "", "", trancheId, currencyId, address(currency));
        LiquidityPool lPool = LiquidityPool(lPool_);
        homePools.updateTrancheTokenPrice(poolId, trancheId, currencyId, 1000000000000000000);

        // invest
        uint256 investmentAmount = 100000000; // 100 * 10**6
        homePools.updateMember(poolId, trancheId, self, type(uint64).max);
        currency.approve(address(investmentManager), investmentAmount);
        currency.mint(self, investmentAmount);
        lPool.requestDeposit(investmentAmount, self);

        // trigger executed collectInvest of the first 50% at a price of 1.2
        uint128 _currencyId = poolManager.currencyAddressToId(address(currency)); // retrieve currencyId
        uint128 currencyPayout = 50000000; // 50 * 10**6
        uint128 firstTrancheTokenPayout = 41666666666666666666; // 50 * 10**18 / 1.2, rounded down
        homePools.isExecutedCollectInvest(
            poolId, trancheId, bytes32(bytes20(self)), _currencyId, currencyPayout, firstTrancheTokenPayout
        );

        // assert deposit & mint values adjusted
        assertEq(lPool.maxDeposit(self), currencyPayout);
        assertEq(lPool.maxMint(self), firstTrancheTokenPayout);

        // deposit price should be ~1.2*10**18
        assertEq(investmentManager.calculateDepositPrice(self, address(lPool)), 1200000000000000000);

        // trigger executed collectInvest of the second 50% at a price of 1.4
        currencyPayout = 50000000; // 50 * 10**6
        uint128 secondTrancheTokenPayout = 35714285714285714285; // 50 * 10**18 / 1.4, rounded down
        homePools.isExecutedCollectInvest(
            poolId, trancheId, bytes32(bytes20(self)), _currencyId, currencyPayout, secondTrancheTokenPayout
        );

        // deposit price should now be 50% * 1.2 + 50% * 1.4 = ~1.3*10**18.
        assertEq(investmentManager.calculateDepositPrice(self, address(lPool)), 1292307692307692307);

        // collect the tranche tokens
        lPool.mint(firstTrancheTokenPayout + secondTrancheTokenPayout, self);
        assertEq(lPool.balanceOf(self), firstTrancheTokenPayout + secondTrancheTokenPayout);

        // redeem
        lPool.approve(address(investmentManager), firstTrancheTokenPayout + secondTrancheTokenPayout);
        lPool.requestRedeem(firstTrancheTokenPayout + secondTrancheTokenPayout, self);

        // trigger executed collectRedeem at a price of 1.5
        // 50% invested at 1.2 and 50% invested at 1.4 leads to ~77 tranche tokens
        // when redeeming at a price of 1.5, this leads to ~115.5 currency
        currencyPayout = 115500000; // 115.5*10**6

        // mint interest into escrow
        currency.mint(address(escrow), currencyPayout - investmentAmount);

        homePools.isExecutedCollectRedeem(
            poolId,
            trancheId,
            bytes32(bytes20(self)),
            _currencyId,
            currencyPayout,
            firstTrancheTokenPayout + secondTrancheTokenPayout
        );

        // redeem price should now be ~1.5*10**18.
        assertEq(investmentManager.calculateRedeemPrice(self, address(lPool)), 1492615384615384615);

        // collect the currency
        lPool.withdraw(currencyPayout, self, self);
        assertEq(currency.balanceOf(self), currencyPayout);
    }

    function testDepositAndRedeemPrecisionWithInverseDecimals(uint64 poolId, bytes16 trancheId, uint128 currencyId)
        public
    {
        vm.assume(currencyId > 0);

        uint8 TRANCHE_TOKEN_DECIMALS = 6; // Like DAI
        uint8 INVESTMENT_CURRENCY_DECIMALS = 18; // 18, like USDC

        ERC20 currency = _newErc20("Currency", "CR", INVESTMENT_CURRENCY_DECIMALS);
        address lPool_ =
            deployLiquidityPool(poolId, TRANCHE_TOKEN_DECIMALS, "", "", trancheId, currencyId, address(currency));
        LiquidityPool lPool = LiquidityPool(lPool_);
        homePools.updateTrancheTokenPrice(poolId, trancheId, currencyId, 1000000000000000000000000000);

        // invest
        uint256 investmentAmount = 100000000000000000000; // 100 * 10**18
        homePools.updateMember(poolId, trancheId, self, type(uint64).max);
        currency.approve(address(investmentManager), investmentAmount);
        currency.mint(self, investmentAmount);
        lPool.requestDeposit(investmentAmount, self);

        // trigger executed collectInvest of the first 50% at a price of 1.2
        uint128 _currencyId = poolManager.currencyAddressToId(address(currency)); // retrieve currencyId
        uint128 currencyPayout = 50000000000000000000; // 50 * 10**18
        uint128 firstTrancheTokenPayout = 41666666; // 50 * 10**6 / 1.2, rounded down
        homePools.isExecutedCollectInvest(
            poolId, trancheId, bytes32(bytes20(self)), _currencyId, currencyPayout, firstTrancheTokenPayout
        );

        // assert deposit & mint values adjusted
        assertEq(lPool.maxDeposit(self), currencyPayout);
        assertEq(lPool.maxMint(self), firstTrancheTokenPayout);

        // deposit price should be ~1.2*10**18
        assertEq(investmentManager.calculateDepositPrice(self, address(lPool)), 1200000019200000307);

        // trigger executed collectInvest of the second 50% at a price of 1.4
        currencyPayout = 50000000000000000000; // 50 * 10**18
        uint128 secondTrancheTokenPayout = 35714285; // 50 * 10**6 / 1.4, rounded down
        homePools.isExecutedCollectInvest(
            poolId, trancheId, bytes32(bytes20(self)), _currencyId, currencyPayout, secondTrancheTokenPayout
        );

        // deposit price should now be 50% * 1.2 + 50% * 1.4 = ~1.3*10**18.
        assertEq(investmentManager.calculateDepositPrice(self, address(lPool)), 1292307715370414612);

        // collect the tranche tokens
        lPool.mint(firstTrancheTokenPayout + secondTrancheTokenPayout, self);
        assertEq(lPool.balanceOf(self), firstTrancheTokenPayout + secondTrancheTokenPayout);

        // redeem
        lPool.approve(address(investmentManager), firstTrancheTokenPayout + secondTrancheTokenPayout);
        lPool.requestRedeem(firstTrancheTokenPayout + secondTrancheTokenPayout, self);

        // trigger executed collectRedeem at a price of 1.5
        // 50% invested at 1.2 and 50% invested at 1.4 leads to ~77 tranche tokens
        // when redeeming at a price of 1.5, this leads to ~115.5 currency
        currencyPayout = 115500000000000000000; // 115.5*10**18

        // mint interest into escrow
        currency.mint(address(escrow), currencyPayout - investmentAmount);

        homePools.isExecutedCollectRedeem(
            poolId,
            trancheId,
            bytes32(bytes20(self)),
            _currencyId,
            currencyPayout,
            firstTrancheTokenPayout + secondTrancheTokenPayout
        );

        // redeem price should now be ~1.5*10**18.
        assertEq(investmentManager.calculateRedeemPrice(self, address(lPool)), 1492615411252828877);

        // // collect the currency
        lPool.withdraw(currencyPayout, self, self);
        assertEq(currency.balanceOf(self), currencyPayout);
    }

    // Test that assumes the swap from usdc (investment currency) to dai (pool currency) has a cost of 1%
    function testDepositAndRedeemPrecisionWithSlippage(uint64 poolId, bytes16 trancheId, uint128 currencyId) public {
        vm.assume(currencyId > 0);

        uint8 INVESTMENT_CURRENCY_DECIMALS = 6; // 6, like USDC
        uint8 TRANCHE_TOKEN_DECIMALS = 18; // Like DAI

        ERC20 currency = _newErc20("Currency", "CR", INVESTMENT_CURRENCY_DECIMALS);
        address lPool_ =
            deployLiquidityPool(poolId, TRANCHE_TOKEN_DECIMALS, "", "", trancheId, currencyId, address(currency));
        LiquidityPool lPool = LiquidityPool(lPool_);

        // price = (100*10**18) /  (99 * 10**18) = 101.010101 * 10**18
        homePools.updateTrancheTokenPrice(poolId, trancheId, currencyId, 1010101010101010101);

        // invest
        uint256 investmentAmount = 100000000; // 100 * 10**6
        homePools.updateMember(poolId, trancheId, self, type(uint64).max);
        currency.approve(address(investmentManager), investmentAmount);
        currency.mint(self, investmentAmount);
        lPool.requestDeposit(investmentAmount, self);

        // trigger executed collectInvest at a tranche token price of 1.2
        uint128 _currencyId = poolManager.currencyAddressToId(address(currency)); // retrieve currencyId
        uint128 currencyPayout = 99000000; // 99 * 10**6

        // invested amount in dai is 99 * 10**18
        // executed at price of 1.2, leads to a tranche token payout of
        // 99 * 10**18 / 1.2 = 82500000000000000000
        uint128 trancheTokenPayout = 82500000000000000000;
        homePools.isExecutedCollectInvest(
            poolId, trancheId, bytes32(bytes20(self)), _currencyId, currencyPayout, trancheTokenPayout
        );

        // assert deposit & mint values adjusted
        assertEq(lPool.maxDeposit(self), currencyPayout);
        assertEq(lPool.maxMint(self), trancheTokenPayout);

        // lp price is value of 1 tranche token in dai
        assertEq(lPool.latestPrice(), 1200000000000000000);

        // lp price is set to the deposit price
        assertEq(investmentManager.calculateDepositPrice(self, address(lPool)), 1200000000000000000);
    }

    // Test that assumes the swap from usdc (investment currency) to dai (pool currency) has a cost of 1%
    function testDepositAndRedeemPrecisionWithSlippageAndWithInverseDecimal(
        uint64 poolId,
        bytes16 trancheId,
        uint128 currencyId
    ) public {
        vm.assume(currencyId > 0);

        uint8 INVESTMENT_CURRENCY_DECIMALS = 18; // 18, like DAI
        uint8 TRANCHE_TOKEN_DECIMALS = 6; // Like USDC

        ERC20 currency = _newErc20("Currency", "CR", INVESTMENT_CURRENCY_DECIMALS);
        address lPool_ =
            deployLiquidityPool(poolId, TRANCHE_TOKEN_DECIMALS, "", "", trancheId, currencyId, address(currency));
        LiquidityPool lPool = LiquidityPool(lPool_);

        // price = (100*10**18) /  (99 * 10**18) = 101.010101 * 10**18
        homePools.updateTrancheTokenPrice(poolId, trancheId, currencyId, 1010101010101010101);

        // invest
        uint256 investmentAmount = 100000000; // 100 * 10**6
        homePools.updateMember(poolId, trancheId, self, type(uint64).max);
        currency.approve(address(investmentManager), investmentAmount);
        currency.mint(self, investmentAmount);
        lPool.requestDeposit(investmentAmount, self);

        // trigger executed collectInvest at a tranche token price of 1.2
        uint128 _currencyId = poolManager.currencyAddressToId(address(currency)); // retrieve currencyId
        uint128 currencyPayout = 99000000000000000000; // 99 * 10**18

        // invested amount in dai is 99 * 10**18
        // executed at price of 1.2, leads to a tranche token payout of
        // 99 * 10**6 / 1.2 = 82500000
        uint128 trancheTokenPayout = 82500000;
        homePools.isExecutedCollectInvest(
            poolId, trancheId, bytes32(bytes20(self)), _currencyId, currencyPayout, trancheTokenPayout
        );

        // assert deposit & mint values adjusted
        assertEq(lPool.maxDeposit(self), currencyPayout);
        assertEq(lPool.maxMint(self), trancheTokenPayout);
        // lp price is value of 1 tranche token in usdc
        assertEq(lPool.latestPrice(), 1200000000000000000);

        // lp price is set to the deposit price
        assertEq(investmentManager.calculateDepositPrice(self, address(lPool)), 1200000000000000000);
    }

    function testAssetShareConversion(uint64 poolId, bytes16 trancheId, uint128 currencyId) public {
        vm.assume(currencyId > 0);

        uint8 INVESTMENT_CURRENCY_DECIMALS = 6; // 6, like USDC
        uint8 TRANCHE_TOKEN_DECIMALS = 18; // Like DAI

        ERC20 currency = _newErc20("Currency", "CR", INVESTMENT_CURRENCY_DECIMALS);
        address lPool_ =
            deployLiquidityPool(poolId, TRANCHE_TOKEN_DECIMALS, "", "", trancheId, currencyId, address(currency));
        LiquidityPool lPool = LiquidityPool(lPool_);
        homePools.updateTrancheTokenPrice(poolId, trancheId, currencyId, 1000000);

        // invest
        uint256 investmentAmount = 100000000; // 100 * 10**6
        homePools.updateMember(poolId, trancheId, self, type(uint64).max);
        currency.approve(address(investmentManager), investmentAmount);
        currency.mint(self, investmentAmount);
        lPool.requestDeposit(investmentAmount, self);

        // trigger executed collectInvest at a price of 1.0
        uint128 _currencyId = poolManager.currencyAddressToId(address(currency)); // retrieve currencyId
        uint128 trancheTokenPayout = 100000000000000000000; // 100 * 10**18
        homePools.isExecutedCollectInvest(
            poolId, trancheId, bytes32(bytes20(self)), _currencyId, uint128(investmentAmount), trancheTokenPayout
        );
        lPool.mint(trancheTokenPayout, self);

        // assert share/asset conversion
        assertEq(lPool.latestPrice(), 1000000000000000000);
        assertEq(lPool.totalSupply(), 100000000000000000000);
        assertEq(lPool.totalAssets(), 100000000);
        assertEq(lPool.convertToShares(100000000), 100000000000000000000); // tranche tokens have 12 more decimals than assets
        assertEq(lPool.convertToAssets(lPool.convertToShares(100000000000000000000)), 100000000000000000000);

        // assert share/asset conversion after price update
        homePools.updateTrancheTokenPrice(poolId, trancheId, currencyId, 1200000000000000000);

        assertEq(lPool.latestPrice(), 1200000000000000000);
        assertEq(lPool.totalAssets(), 120000000);
        assertEq(lPool.convertToShares(120000000), 100000000000000000000); // tranche tokens have 12 more decimals than assets
        assertEq(lPool.convertToAssets(lPool.convertToShares(120000000000000000000)), 120000000000000000000);
    }

    function testAssetShareConversionWithInverseDecimals(uint64 poolId, bytes16 trancheId, uint128 currencyId) public {
        vm.assume(currencyId > 0);

        uint8 INVESTMENT_CURRENCY_DECIMALS = 18; // 18, like DAI
        uint8 TRANCHE_TOKEN_DECIMALS = 6; // Like USDC

        ERC20 currency = _newErc20("Currency", "CR", INVESTMENT_CURRENCY_DECIMALS);
        address lPool_ =
            deployLiquidityPool(poolId, TRANCHE_TOKEN_DECIMALS, "", "", trancheId, currencyId, address(currency));
        LiquidityPool lPool = LiquidityPool(lPool_);
        homePools.updateTrancheTokenPrice(poolId, trancheId, currencyId, 1000000);

        // invest
        uint256 investmentAmount = 100000000000000000000; // 100 * 10**18
        homePools.updateMember(poolId, trancheId, self, type(uint64).max);
        currency.approve(address(investmentManager), investmentAmount);
        currency.mint(self, investmentAmount);
        lPool.requestDeposit(investmentAmount, self);

        // trigger executed collectInvest at a price of 1.0
        uint128 _currencyId = poolManager.currencyAddressToId(address(currency)); // retrieve currencyId
        uint128 trancheTokenPayout = 100000000; // 100 * 10**6
        homePools.isExecutedCollectInvest(
            poolId, trancheId, bytes32(bytes20(self)), _currencyId, uint128(investmentAmount), trancheTokenPayout
        );
        lPool.mint(trancheTokenPayout, self);

        // assert share/asset conversion
        assertEq(lPool.latestPrice(), 1000000000000000000);
        assertEq(lPool.totalSupply(), 100000000);
        assertEq(lPool.totalAssets(), 100000000000000000000);
        assertEq(lPool.convertToShares(100000000000000000000), 100000000); // tranche tokens have 12 less decimals than assets
        assertEq(lPool.convertToAssets(lPool.convertToShares(100000000000000000000)), 100000000000000000000);

        // assert share/asset conversion after price update
        homePools.updateTrancheTokenPrice(poolId, trancheId, currencyId, 1200000000000000000);

        assertEq(lPool.latestPrice(), 1200000000000000000);
        assertEq(lPool.totalAssets(), 120000000000000000000);
        assertEq(lPool.convertToShares(120000000000000000000), 100000000); // tranche tokens have 12 less decimals than assets
        assertEq(lPool.convertToAssets(lPool.convertToShares(120000000000000000000)), 120000000000000000000);
    }

    function testCancelDepositOrder(
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

        address lPool_ = deployLiquidityPool(poolId, erc20.decimals(), tokenName, tokenSymbol, trancheId, currencyId);
        LiquidityPool lPool = LiquidityPool(lPool_);
        homePools.updateTrancheTokenPrice(poolId, trancheId, currencyId, price);
        erc20.mint(self, amount);
        erc20.approve(address(investmentManager), amount); // add allowance
        homePools.updateMember(poolId, trancheId, self, validUntil);

        lPool.requestDeposit(amount, self);

        assertEq(erc20.balanceOf(address(escrow)), amount);
        assertEq(erc20.balanceOf(address(self)), 0);

        // check message was send out to centchain
        lPool.requestDeposit(0, self);
        bytes memory cancelOrderMessage =
            Messages.formatCancelInvestOrder(poolId, trancheId, _addressToBytes32(self), currencyId);
        assertEq(cancelOrderMessage, mockXcmRouter.values_bytes("send"));

        homePools.isExecutedDecreaseInvestOrder(poolId, trancheId, _addressToBytes32(self), currencyId, uint128(amount));
        assertEq(erc20.balanceOf(address(escrow)), 0);
        assertEq(erc20.balanceOf(address(self)), amount);
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

        address lPool_ = deployLiquidityPool(poolId, erc20.decimals(), tokenName, tokenSymbol, trancheId, currencyId);
        LiquidityPool lPool = LiquidityPool(lPool_);
        homePools.updateTrancheTokenPrice(poolId, trancheId, currencyId, price);

        erc20.mint(self, amount);

        // will fail - user not member: can not receive trancheToken
        vm.expectRevert(bytes("InvestmentManager/not-a-member"));
        lPool.requestDeposit(amount, self);
        homePools.updateMember(poolId, trancheId, self, validUntil); // add user as member

        // // will fail - user did not give currency allowance to investmentManager
        vm.expectRevert(bytes("SafeTransferLib/safe-transfer-from-failed"));
        lPool.requestDeposit(amount, self);

        // success
        erc20.approve(address(investmentManager), amount); // add allowance
        lPool.requestDeposit(amount, self);

        // fail: no currency left
        vm.expectRevert(bytes("SafeTransferLib/safe-transfer-from-failed"));
        lPool.requestDeposit(amount, self);

        // ensure funds are locked in escrow
        assertEq(erc20.balanceOf(address(escrow)), amount);
        assertEq(erc20.balanceOf(self), 0);

        // trigger executed collectInvest
        uint128 _currencyId = poolManager.currencyAddressToId(address(erc20)); // retrieve currencyId
        uint128 trancheTokensPayout = uint128(amount * 10 ** 27 / price); // trancheTokenPrice = 2$
        assertApproxEqAbs(trancheTokensPayout, amount / 2, 2);
        homePools.isExecutedCollectInvest(
            poolId, trancheId, bytes32(bytes20(self)), _currencyId, uint128(amount), trancheTokensPayout
        );

        // assert deposit & mint values adjusted
        assertEq(lPool.maxMint(self), trancheTokensPayout); // max deposit
        assertEq(lPool.maxDeposit(self), amount); // max deposit
        // assert tranche tokens minted
        assertEq(lPool.balanceOf(address(escrow)), trancheTokensPayout);
        // assert conversions
        assertEq(lPool.previewDeposit(amount), trancheTokensPayout);
        assertApproxEqAbs(lPool.previewMint(trancheTokensPayout), amount, 1);

        // deposit 50% of the amount
        uint256 share = 2;
        lPool.deposit(amount / 2, self); // mint half the amount

        // Allow 2 difference because of rounding
        assertApproxEqAbs(lPool.balanceOf(self), trancheTokensPayout / 2, 2);
        assertApproxEqAbs(lPool.balanceOf(address(escrow)), trancheTokensPayout - trancheTokensPayout / 2, 2);
        assertApproxEqAbs(lPool.maxMint(self), trancheTokensPayout - trancheTokensPayout / 2, 2);
        assertApproxEqAbs(lPool.maxDeposit(self), amount - amount / 2, 2);

        // mint the rest
        lPool.mint(lPool.maxMint(self), self);
        assertEq(lPool.balanceOf(self), trancheTokensPayout - lPool.maxMint(self));
        assertTrue(lPool.balanceOf(address(escrow)) <= 1);
        assertTrue(lPool.maxMint(self) <= 1);

        // remainder is rounding difference
        assertTrue(lPool.maxDeposit(self) <= amount * 0.01e18);
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

        LiquidityPool lPool =
            LiquidityPool(deployLiquidityPool(poolId, erc20.decimals(), tokenName, tokenSymbol, trancheId, currencyId));
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
                            erc20.PERMIT_TYPEHASH(), investor, address(investmentManager), amount, 0, block.timestamp
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
            poolManager.currencyAddressToId(address(erc20)),
            uint128(amount),
            uint128(amount)
        );

        uint256 maxMint = lPool.maxMint(investor);
        lPool.mint(maxMint, investor);

        TrancheToken trancheToken = TrancheToken(address(lPool.share()));
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
                            trancheToken.PERMIT_TYPEHASH(),
                            investor,
                            address(investmentManager),
                            maxMint,
                            0,
                            block.timestamp
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
        uint64 validUntil,
        address random
    ) public {
        vm.assume(currencyId > 0);
        vm.assume(random != address(0));
        vm.assume(amount < MAX_UINT128);
        vm.assume(amount > 4);
        vm.assume(validUntil >= block.timestamp);
        price = 1;

        address lPool_ = deployLiquidityPool(poolId, erc20.decimals(), tokenName, tokenSymbol, trancheId, currencyId);
        deposit(lPool_, poolId, trancheId, amount, validUntil); // deposit funds first
        LiquidityPool lPool = LiquidityPool(lPool_);
        homePools.updateTrancheTokenPrice(poolId, trancheId, currencyId, price);

        // will fail - user did not give tranche token allowance to investmentManager
        vm.expectRevert(bytes("ERC20/insufficient-allowance"));
        lPool.requestRedeem(amount, self);
        lPool.approve(address(investmentManager), amount); // add allowance

        // success
        lPool.requestRedeem(amount, self);
        assertEq(lPool.balanceOf(address(escrow)), amount);

        // fail: no tokens left
        lPool.approve(address(investmentManager), amount); // add allowance
        vm.expectRevert(bytes("ERC20/insufficient-balance"));
        lPool.requestRedeem(amount, self);

        // trigger executed collectRedeem
        uint128 _currencyId = poolManager.currencyAddressToId(address(erc20)); // retrieve currencyId
        uint128 currencyPayout = uint128(amount) / uint128(price);
        homePools.isExecutedCollectRedeem(
            poolId, trancheId, bytes32(bytes20(self)), _currencyId, currencyPayout, uint128(amount)
        );

        // assert withdraw & redeem values adjusted
        assertEq(lPool.maxWithdraw(self), currencyPayout); // max deposit
        assertEq(lPool.maxRedeem(self), amount); // max deposit
        assertEq(lPool.balanceOf(address(escrow)), 0);
        assertEq(erc20.balanceOf(address(userEscrow)), currencyPayout);
        // assert conversions
        assertEq(lPool.previewWithdraw(currencyPayout), amount);
        assertEq(lPool.previewRedeem(amount), currencyPayout);

        // success
        lPool.redeem(amount / 2, self, self); // redeem half the amount to own wallet

        // fail -> random has no approval to receive funds
        vm.expectRevert(bytes("UserEscrow/receiver-has-no-allowance"));
        lPool.redeem(amount / 2, random, self); // redeem half the amount to another wallet

        // fail -> receiver needs to have max approval
        erc20.approve(random, lPool.maxRedeem(self));
        vm.expectRevert(bytes("UserEscrow/receiver-has-no-allowance"));
        lPool.redeem(amount / 2, random, self); // redeem half the amount to random wallet

        // success
        erc20.approve(random, type(uint256).max);
        lPool.redeem(amount / 2, random, self); // redeem half the amount to random wallet

        assertEq(lPool.balanceOf(self), 0);
        assertTrue(lPool.balanceOf(address(escrow)) <= 1);
        assertTrue(erc20.balanceOf(address(userEscrow)) <= 1);

        assertEq(erc20.balanceOf(self), (amount / 2));
        assertEq(erc20.balanceOf(random), (amount / 2));
        assertTrue(lPool.maxWithdraw(self) <= 1);
        assertTrue(lPool.maxRedeem(self) <= 1);
    }

    function testCancelRedeemOrder(
        uint64 poolId,
        uint8 decimals,
        string memory tokenName,
        string memory tokenSymbol,
        bytes16 trancheId,
        uint128 price,
        uint128 currencyId,
        uint256 amount,
        uint64 validUntil,
        address random
    ) public {
        vm.assume(currencyId > 0);
        vm.assume(random != address(0));
        vm.assume(amount < MAX_UINT128);
        vm.assume(amount > 1);
        vm.assume(validUntil >= block.timestamp);
        price = 1;

        address lPool_ = deployLiquidityPool(poolId, erc20.decimals(), tokenName, tokenSymbol, trancheId, currencyId);
        deposit(lPool_, poolId, trancheId, amount, validUntil); // deposit funds first
        LiquidityPool lPool = LiquidityPool(lPool_);
        lPool.approve(address(investmentManager), amount); // add allowance
        lPool.requestRedeem(amount, self);

        assertEq(lPool.balanceOf(address(escrow)), amount);
        assertEq(lPool.balanceOf(self), 0);

        // check message was send out to centchain
        lPool.requestRedeem(0, self);
        bytes memory cancelOrderMessage =
            Messages.formatCancelRedeemOrder(poolId, trancheId, _addressToBytes32(self), currencyId);
        assertEq(cancelOrderMessage, mockXcmRouter.values_bytes("send"));

        homePools.isExecutedDecreaseRedeemOrder(poolId, trancheId, _addressToBytes32(self), currencyId, uint128(amount));
        assertEq(lPool.balanceOf(address(escrow)), 0);
        assertEq(lPool.balanceOf(address(self)), amount);
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
        uint64 validUntil,
        address random
    ) public {
        vm.assume(currencyId > 0);
        vm.assume(amount < MAX_UINT128);
        vm.assume(random != address(0));
        vm.assume(amount > 1);
        vm.assume(validUntil >= block.timestamp);
        price = 1;

        address lPool_ = deployLiquidityPool(poolId, erc20.decimals(), tokenName, tokenSymbol, trancheId, currencyId);
        deposit(lPool_, poolId, trancheId, amount, validUntil); // deposit funds first
        LiquidityPool lPool = LiquidityPool(lPool_);
        homePools.updateTrancheTokenPrice(poolId, trancheId, currencyId, price);

        // will fail - user did not give tranche token allowance to investmentManager
        vm.expectRevert(bytes("SafeTransferLib/safe-transfer-from-failed"));
        lPool.requestDeposit(amount, self);
        lPool.approve(address(investmentManager), amount); // add allowance

        lPool.requestRedeem(amount, self);
        assertEq(lPool.balanceOf(address(escrow)), amount);
        assertEq(erc20.balanceOf(address(userEscrow)), 0);

        // trigger executed collectRedeem
        uint128 _currencyId = poolManager.currencyAddressToId(address(erc20)); // retrieve currencyId
        uint128 currencyPayout = uint128(amount) / price;
        homePools.isExecutedCollectRedeem(
            poolId, trancheId, bytes32(bytes20(self)), _currencyId, currencyPayout, uint128(amount)
        );

        // assert withdraw & redeem values adjusted
        assertEq(lPool.maxWithdraw(self), currencyPayout); // max deposit
        assertEq(lPool.maxRedeem(self), amount); // max deposit
        assertEq(lPool.balanceOf(address(escrow)), 0);
        assertEq(erc20.balanceOf(address(userEscrow)), currencyPayout);

        lPool.withdraw(amount / 2, self, self); // withdraw half teh amount

        // fail -> random has no approval to receive funds
        vm.expectRevert(bytes("UserEscrow/receiver-has-no-allowance"));
        lPool.withdraw(amount / 2, random, self); // redeem half the amount to another wallet

        // fail -> receiver needs to have max approval
        erc20.approve(random, lPool.maxWithdraw(self));
        vm.expectRevert(bytes("UserEscrow/receiver-has-no-allowance"));
        lPool.withdraw(amount / 2, random, self); // redeem half the amount to random wallet

        // success
        erc20.approve(random, type(uint256).max);
        lPool.withdraw(amount / 2, random, self); // redeem half the amount to random wallet

        assertTrue(lPool.balanceOf(self) <= 1);
        assertTrue(erc20.balanceOf(address(userEscrow)) <= 1);
        assertEq(erc20.balanceOf(self), currencyPayout / 2);
        assertEq(erc20.balanceOf(random), currencyPayout / 2);
        assertTrue(lPool.maxRedeem(self) <= 1);
        assertTrue(lPool.maxWithdraw(self) <= 1);
    }

    function testDecreaseDepositRequest(
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

        address lPool_ = deployLiquidityPool(poolId, erc20.decimals(), tokenName, tokenSymbol, trancheId, currencyId);
        LiquidityPool lPool = LiquidityPool(lPool_);
        homePools.updateTrancheTokenPrice(poolId, trancheId, currencyId, price);

        erc20.mint(self, amount);
        homePools.updateMember(poolId, trancheId, self, validUntil); // add user as member
        erc20.approve(address(investmentManager), amount); // add allowance
        lPool.requestDeposit(amount, self);

        assertEq(erc20.balanceOf(address(escrow)), amount);
        assertEq(erc20.balanceOf(self), 0);

        // decrease deposit request
        lPool.decreaseDepositRequest(amount, self);
        homePools.isExecutedDecreaseInvestOrder(poolId, trancheId, bytes32(bytes20(self)), currencyId, uint128(amount));

        assertEq(erc20.balanceOf(address(escrow)), 0);
        assertEq(erc20.balanceOf(self), amount);
    }

    function testDecreaseRedeemRequest(
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

        address lPool_ = deployLiquidityPool(poolId, erc20.decimals(), tokenName, tokenSymbol, trancheId, currencyId);
        deposit(lPool_, poolId, trancheId, amount, validUntil); // deposit funds first
        LiquidityPool lPool = LiquidityPool(lPool_);
        homePools.updateTrancheTokenPrice(poolId, trancheId, currencyId, price);

        lPool.approve(address(investmentManager), amount);
        lPool.requestRedeem(amount, self);

        assertEq(lPool.balanceOf(address(escrow)), amount);
        assertEq(lPool.balanceOf(self), 0);

        // decrease redeem request
        lPool.decreaseRedeemRequest(amount, self);
        homePools.isExecutedDecreaseRedeemOrder(poolId, trancheId, bytes32(bytes20(self)), currencyId, uint128(amount));

        assertEq(lPool.balanceOf(address(escrow)), 0);
        assertEq(lPool.balanceOf(self), amount);
    }

    function testCollectInvest(
        uint64 poolId,
        bytes16 trancheId,
        string memory tokenName,
        string memory tokenSymbol,
        uint8 decimals,
        uint128 price,
        uint128 currencyId,
        uint64 validUntil,
        uint128 amount
    ) public {
        vm.assume(amount > 0);
        vm.assume(currencyId > 0);
        vm.assume(decimals > 0);
        vm.assume(validUntil > block.timestamp + 7 days);

        address lPool_ = deployLiquidityPool(poolId, decimals, tokenName, tokenSymbol, trancheId, currencyId);
        LiquidityPool lPool = LiquidityPool(lPool_);
        homePools.updateTrancheTokenPrice(poolId, trancheId, currencyId, price);

        vm.expectRevert(bytes("InvestmentManager/not-a-member"));
        lPool.collectDeposit(self);

        homePools.updateMember(poolId, trancheId, self, validUntil);
        lPool.collectDeposit(self);
    }

    function testCollectRedeem(
        uint64 poolId,
        bytes16 trancheId,
        string memory tokenName,
        string memory tokenSymbol,
        uint8 decimals,
        uint128 price,
        uint128 currencyId,
        uint8 trancheDecimals,
        uint64 validUntil,
        uint128 amount
    ) public {
        vm.assume(amount > 0);
        vm.assume(currencyId > 0);
        vm.assume(trancheDecimals > 0);
        vm.assume(validUntil > block.timestamp + 7 days);

        address lPool_ = deployLiquidityPool(poolId, decimals, tokenName, tokenSymbol, trancheId, currencyId);
        LiquidityPool lPool = LiquidityPool(lPool_);
        homePools.allowPoolCurrency(poolId, currencyId);
        homePools.updateTrancheTokenPrice(poolId, trancheId, currencyId, price);

        vm.expectRevert(bytes("InvestmentManager/not-a-member"));
        lPool.collectRedeem(self);
        homePools.updateMember(poolId, trancheId, self, validUntil);

        lPool.collectRedeem(self);
    }

    // helpers
    function deposit(address _lPool, uint64 poolId, bytes16 trancheId, uint256 amount, uint64 validUntil) public {
        LiquidityPool lPool = LiquidityPool(_lPool);
        erc20.mint(self, amount);
        homePools.updateMember(poolId, trancheId, self, validUntil); // add user as member
        erc20.approve(address(investmentManager), amount); // add allowance
        lPool.requestDeposit(amount, self);
        // trigger executed collectInvest
        uint128 currencyId = poolManager.currencyAddressToId(address(erc20)); // retrieve currencyId
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
        investor.approve(address(erc20), address(investmentManager), amount); // add allowance
        investor.requestDeposit(_lPool, amount, _investor);
        uint128 currencyId = poolManager.currencyAddressToId(address(erc20)); // retrieve currencyId
        homePools.isExecutedCollectInvest(
            poolId, trancheId, bytes32(bytes20(_investor)), currencyId, uint128(amount), uint128(amount)
        );
        investor.deposit(_lPool, amount, _investor); // deposit the amount
    }
}
