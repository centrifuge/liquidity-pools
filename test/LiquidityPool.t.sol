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
    }

    // --- Administration ---
    function testFile() public {
        address lPool_ = deploySimplePool();
        LiquidityPool lPool = LiquidityPool(lPool_);

        vm.expectRevert(bytes("Auth/not-authorized"));
        lPool.file("investmentManager", self);

        root.relyContract(lPool_, self);
        lPool.file("investmentManager", self);

        vm.expectRevert(bytes("LiquidityPool/file-unrecognized-param"));
        lPool.file("random", self);
    }

    // --- uint128 type checks ---
    // Make sure all function calls would fail when overflow uint128
    function testAssertUint128(uint256 amount, address random) public {
        vm.assume(amount > MAX_UINT128); // amount has to overflow UINT128
        vm.assume(random.code.length == 0);
        address lPool_ = deploySimplePool();
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

    function testDepositWithApproval(uint256 deposit1, uint256 deposit2) public {
        deposit1 = uint128(bound(deposit1, 2, MAX_UINT128));
        deposit2 = uint128(bound(deposit2, 2, MAX_UINT128));
        uint256 amount = deposit1 + deposit2;

        address lPool_ = deploySimplePool();
        LiquidityPool lPool = LiquidityPool(lPool_);

        erc20.mint(investor, type(uint256).max);
        vm.prank(investor);
        erc20.approve(address(investmentManager), type(uint256).max);
        centrifugeChain.updateMember(lPool.poolId(), lPool.trancheId(), investor, type(uint64).max); // add user as member

        // fail: no approval
        vm.expectRevert(bytes("LiquidityPool/no-approval"));
        lPool.requestDeposit(deposit1, investor);

        // investor gives approval to self
        vm.prank(investor);
        erc20.approve(self, amount);
        // fail: even if investor grants approval to self
        vm.expectRevert(bytes("LiquidityPool/no-approval"));
        lPool.requestDeposit(deposit1, investor);

        // fail: ward can not make requests on behalf of investor
        root.relyContract(lPool_, self);
        vm.expectRevert(bytes("LiquidityPool/no-approval"));
        lPool.requestDeposit(deposit1, investor);

        // success - investor can requestDeposit
        vm.prank(investor);
        lPool.requestDeposit(deposit2, investor);
    }

    function testRedeemWithApproval(uint256 redemption1, uint256 redemption2) public {
        redemption1 = uint128(bound(redemption1, 2, MAX_UINT128));
        redemption2 = uint128(bound(redemption2, 2, MAX_UINT128));
        uint256 amount = redemption1 + redemption2;
        vm.assume(amountAssumption(amount));

        address lPool_ = deploySimplePool();
        LiquidityPool lPool = LiquidityPool(lPool_);

        deposit(lPool_, investor, amount); // deposit funds first // deposit funds first
        vm.prank(investor);
        lPool.approve(address(investmentManager), type(uint256).max);

        // fail: self can not claim for investor
        vm.expectRevert(bytes("LiquidityPool/no-approval"));
        lPool.requestRedeem(amount, investor);

        // investor gives approval to deployer / self
        vm.prank(investor);
        lPool.approve(self, amount);

        // fail: even if investor grants approval to deployer / self
        vm.expectRevert(bytes("LiquidityPool/no-approval"));
        lPool.requestRedeem(amount, investor);

        // success - investor can requestRedeem
        vm.prank(investor);
        lPool.requestRedeem(amount, investor);

        // failf: ward can not requestRedeem on behalf of investor
        vm.expectRevert(bytes("LiquidityPool/no-approval"));
        lPool.requestRedeem(amount, investor);

        uint128 tokenAmount = uint128(lPool.balanceOf(address(escrow)));
        centrifugeChain.isExecutedCollectRedeem(
            lPool.poolId(),
            lPool.trancheId(),
            bytes32(bytes20(investor)),
            defaultCurrencyId,
            uint128(amount),
            uint128(tokenAmount),
            0
        );

        assertEq(lPool.maxRedeem(investor), tokenAmount);
        assertEq(lPool.maxWithdraw(investor), uint128(amount));

        // test for both scenarios redeem & withdraw

        // fail: self cannot redeem for investor
        vm.expectRevert(bytes("LiquidityPool/no-approval"));
        lPool.redeem(redemption1, investor, investor);
        vm.expectRevert(bytes("LiquidityPool/no-approval"));
        lPool.withdraw(redemption1, investor, investor);

        // fail: ward can not make requests on behalf of investor
        root.relyContract(lPool_, self);
        vm.expectRevert(bytes("LiquidityPool/no-approval"));
        lPool.redeem(redemption1, investor, investor);
        vm.expectRevert(bytes("LiquidityPool/no-approval"));
        lPool.withdraw(redemption1, investor, investor);

        // investor redeems rest for himself
        vm.prank(investor);
        lPool.redeem(redemption1, investor, investor);
        vm.prank(investor);
        lPool.withdraw(redemption2, investor, investor);
    }

    function testMint(uint256 amount) public {
        amount = uint128(bound(amount, 2, MAX_UINT128));

        address lPool_ = deploySimplePool();
        LiquidityPool lPool = LiquidityPool(lPool_);

        vm.expectRevert(bytes("Auth/not-authorized"));
        lPool.mint(investor, amount);

        root.relyContract(lPool_, self); // give self auth permissions

        vm.expectRevert(bytes("RestrictionManager/destination-not-a-member"));
        lPool.mint(investor, amount);
        centrifugeChain.updateMember(lPool.poolId(), lPool.trancheId(), investor, type(uint64).max); // add investor as member

        // success
        lPool.mint(investor, amount);
        assertEq(lPool.balanceOf(investor), amount);
        assertEq(lPool.balanceOf(investor), lPool.share().balanceOf(investor));
    }

    function testBurn(uint256 amount) public {
        amount = uint128(bound(amount, 2, MAX_UINT128));

        address lPool_ = deploySimplePool();
        LiquidityPool lPool = LiquidityPool(lPool_);

        root.relyContract(lPool_, self); // give self auth permissions
        centrifugeChain.updateMember(lPool.poolId(), lPool.trancheId(), investor, type(uint64).max); // add investor as member

        lPool.mint(investor, amount);
        root.denyContract(lPool_, self); // remove auth permissions from self

        vm.expectRevert(bytes("Auth/not-authorized"));
        lPool.burn(investor, amount);

        root.relyContract(lPool_, self); // give self auth permissions
        vm.expectRevert(bytes("ERC20/insufficient-allowance"));
        lPool.burn(investor, amount);

        // success
        vm.prank(investor);
        lPool.approve(lPool_, amount); // approve LP to burn tokens
        lPool.burn(investor, amount);

        assertEq(lPool.balanceOf(investor), 0);
        assertEq(lPool.balanceOf(investor), lPool.share().balanceOf(investor));
    }

    function testTransferFrom(uint256 amount, uint256 transferAmount) public {
        transferAmount = uint128(bound(transferAmount, 2, MAX_UINT128));
        amount = uint128(bound(amount, 2, MAX_UINT128));
        vm.assume(transferAmount <= amount);

        address lPool_ = deploySimplePool();

        deposit(lPool_, investor, amount); // deposit funds first // deposit funds first
        LiquidityPool lPool = LiquidityPool(lPool_);
        centrifugeChain.updateMember(lPool.poolId(), lPool.trancheId(), self, type(uint64).max); // put self on memberlist to be able to receive tranche tokens
        centrifugeChain.updateTrancheTokenPrice(lPool.poolId(), lPool.trancheId(), defaultCurrencyId, defaultPrice);

        TrancheToken trancheToken = TrancheToken(address(lPool.share()));
        assertEq(trancheToken.isTrustedForwarder(lPool_), true); // Lpool is trusted forwarder on token

        uint256 initBalance = lPool.balanceOf(investor);

        // replacing msg sender only possible for trusted forwarder
        assertEq(trancheToken.isTrustedForwarder(self), false); // self is not trusted forwarder on token
        (bool success,) = address(trancheToken).call(
            abi.encodeWithSelector(
                bytes4(keccak256(bytes("transferFrom(address,address,uint256)"))),
                investor,
                self,
                transferAmount,
                investor
            )
        );
        assertEq(success, false);

        // remove LiquidityPool as trusted forwarder
        root.relyContract(address(trancheToken), self);
        trancheToken.removeLiquidityPool(lPool_);
        assertEq(trancheToken.isTrustedForwarder(lPool_), false); // adding trusted forwarder works

        vm.expectRevert(bytes("ERC20/insufficient-allowance"));
        vm.prank(investor);
        lPool.transferFrom(investor, self, transferAmount);

        // add liquidityPool back as trusted forwarder
        trancheToken.addLiquidityPool(lPool_);

        vm.prank(investor);
        lPool.transferFrom(investor, self, transferAmount);
        assertEq(lPool.balanceOf(investor), (initBalance - transferAmount));
        assertEq(lPool.balanceOf(self), transferAmount);
    }

    function testApprove(uint256 amount, uint256 approvalAmount) public {
        amount = uint128(bound(amount, 2, MAX_UINT128));
        approvalAmount = uint128(bound(approvalAmount, 2, MAX_UINT128));
        vm.assume(amount > approvalAmount);

        address receiver = makeAddr("receiver");
        address lPool_ = deploySimplePool();
        LiquidityPool lPool = LiquidityPool(lPool_);
        centrifugeChain.updateTrancheTokenPrice(lPool.poolId(), lPool.trancheId(), defaultCurrencyId, defaultPrice);

        TrancheToken trancheToken = TrancheToken(address(lPool.share()));
        assertTrue(trancheToken.isTrustedForwarder(lPool_)); // Lpool is not trusted forwarder on token

        // replacing msg sender only possible for trusted forwarder
        assertEq(trancheToken.isTrustedForwarder(self), false); // Lpool is not trusted forwarder on token
        (bool success,) = address(trancheToken).call(
            abi.encodeWithSelector(
                bytes4(keccak256(bytes("approve(address,uint256)"))), receiver, approvalAmount, investor
            )
        );

        assertEq(success, true);
        assertEq(lPool.allowance(self, receiver), approvalAmount);
        assertEq(lPool.allowance(investor, receiver), 0);

        // remove LiquidityPool as trusted forwarder
        root.relyContract(address(trancheToken), self);
        trancheToken.removeLiquidityPool(lPool_);
        assertEq(trancheToken.isTrustedForwarder(lPool_), false); // adding trusted forwarder works

        vm.prank(investor);
        lPool.approve(receiver, approvalAmount);
        assertEq(lPool.allowance(lPool_, receiver), approvalAmount);
        assertEq(lPool.allowance(investor, receiver), 0);

        // add liquidityPool back as trusted forwarder
        trancheToken.addLiquidityPool(lPool_);

        vm.prank(investor);
        lPool.approve(receiver, approvalAmount);
        assertEq(lPool.allowance(investor, receiver), approvalAmount);
    }

    function testTransfer(uint256 transferAmount, uint256 amount) public {
        transferAmount = uint128(bound(transferAmount, 2, MAX_UINT128));
        amount = uint128(bound(amount, 2, MAX_UINT128));
        vm.assume(transferAmount <= amount);

        address lPool_ = deploySimplePool();

        deposit(lPool_, investor, amount); // deposit funds first // deposit funds first
        LiquidityPool lPool = LiquidityPool(lPool_);
        centrifugeChain.updateMember(lPool.poolId(), lPool.trancheId(), self, type(uint64).max); // put self on memberlist to be able to receive tranche tokens

        TrancheToken trancheToken = TrancheToken(address(lPool.share()));
        assertTrue(trancheToken.isTrustedForwarder(lPool_)); // Lpool is not trusted forwarder on token

        uint256 initBalance = lPool.balanceOf(investor);
        // replacing msg sender only possible for trusted forwarder
        assertEq(trancheToken.isTrustedForwarder(self), false); // Lpool is not trusted forwarder on token
        (bool success,) = address(trancheToken).call(
            abi.encodeWithSelector(
                bytes4(keccak256(bytes("transfer(address,uint256)"))), self, transferAmount, investor
            )
        );
        assertEq(success, false);

        // remove LiquidityPool as trusted forwarder
        root.relyContract(address(trancheToken), self);
        trancheToken.removeLiquidityPool(lPool_);
        assertEq(trancheToken.isTrustedForwarder(lPool_), false); // adding trusted forwarder works

        vm.expectRevert(bytes("ERC20/insufficient-balance"));
        vm.prank(investor);
        lPool.transfer(self, transferAmount);

        // add liquidityPool back as trusted forwarder
        trancheToken.addLiquidityPool(lPool_);
        vm.prank(investor);
        lPool.transfer(self, transferAmount);

        assertEq(lPool.balanceOf(investor), (initBalance - transferAmount));
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
        centrifugeChain.updateTrancheTokenPrice(poolId, trancheId, currencyId, 1000000000000000000);

        // invest
        uint256 investmentAmount = 100000000; // 100 * 10**6
        centrifugeChain.updateMember(poolId, trancheId, self, type(uint64).max);
        currency.approve(address(investmentManager), investmentAmount);
        currency.mint(self, investmentAmount);
        lPool.requestDeposit(investmentAmount, self);

        // trigger executed collectInvest of the first 50% at a price of 1.2
        uint128 _currencyId = poolManager.currencyAddressToId(address(currency)); // retrieve currencyId
        uint128 currencyPayout = 50000000; // 50 * 10**6
        uint128 firstTrancheTokenPayout = 41666666666666666666; // 50 * 10**18 / 1.2, rounded down
        centrifugeChain.isExecutedCollectInvest(
            poolId,
            trancheId,
            bytes32(bytes20(self)),
            _currencyId,
            currencyPayout,
            firstTrancheTokenPayout,
            currencyPayout / 2
        );

        // assert deposit & mint values adjusted
        assertEq(lPool.maxDeposit(self), currencyPayout);
        assertEq(lPool.maxMint(self), firstTrancheTokenPayout);

        // deposit price should be ~1.2*10**18
        assertEq(investmentManager.calculateDepositPrice(self, address(lPool)), 1200000000000000000);

        // trigger executed collectInvest of the second 50% at a price of 1.4
        currencyPayout = 50000000; // 50 * 10**6
        uint128 secondTrancheTokenPayout = 35714285714285714285; // 50 * 10**18 / 1.4, rounded down
        centrifugeChain.isExecutedCollectInvest(
            poolId, trancheId, bytes32(bytes20(self)), _currencyId, currencyPayout, secondTrancheTokenPayout, 0
        );

        // deposit price should now be 50% * 1.2 + 50% * 1.4 = ~1.3*10**18.
        assertEq(investmentManager.calculateDepositPrice(self, address(lPool)), 1292307692307692307);
        assertEq(lPool.userDepositRequest(self), 0);

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

        centrifugeChain.isExecutedCollectRedeem(
            poolId,
            trancheId,
            bytes32(bytes20(self)),
            _currencyId,
            currencyPayout,
            firstTrancheTokenPayout + secondTrancheTokenPayout,
            0
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
        centrifugeChain.updateTrancheTokenPrice(poolId, trancheId, currencyId, 1000000000000000000000000000);

        // invest
        uint256 investmentAmount = 100000000000000000000; // 100 * 10**18
        centrifugeChain.updateMember(poolId, trancheId, self, type(uint64).max);
        currency.approve(address(investmentManager), investmentAmount);
        currency.mint(self, investmentAmount);
        lPool.requestDeposit(investmentAmount, self);

        // trigger executed collectInvest of the first 50% at a price of 1.2
        uint128 _currencyId = poolManager.currencyAddressToId(address(currency)); // retrieve currencyId
        uint128 currencyPayout = 50000000000000000000; // 50 * 10**18
        uint128 firstTrancheTokenPayout = 41666666; // 50 * 10**6 / 1.2, rounded down
        centrifugeChain.isExecutedCollectInvest(
            poolId,
            trancheId,
            bytes32(bytes20(self)),
            _currencyId,
            currencyPayout,
            firstTrancheTokenPayout,
            currencyPayout / 2
        );

        // assert deposit & mint values adjusted
        assertEq(lPool.maxDeposit(self), currencyPayout);
        assertEq(lPool.maxMint(self), firstTrancheTokenPayout);

        // deposit price should be ~1.2*10**18
        assertEq(investmentManager.calculateDepositPrice(self, address(lPool)), 1200000019200000307);

        // trigger executed collectInvest of the second 50% at a price of 1.4
        currencyPayout = 50000000000000000000; // 50 * 10**18
        uint128 secondTrancheTokenPayout = 35714285; // 50 * 10**6 / 1.4, rounded down
        centrifugeChain.isExecutedCollectInvest(
            poolId, trancheId, bytes32(bytes20(self)), _currencyId, currencyPayout, secondTrancheTokenPayout, 0
        );

        // deposit price should now be 50% * 1.2 + 50% * 1.4 = ~1.3*10**18.
        assertEq(investmentManager.calculateDepositPrice(self, address(lPool)), 1292307715370414612);
        assertEq(lPool.userDepositRequest(self), 0);

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

        centrifugeChain.isExecutedCollectRedeem(
            poolId,
            trancheId,
            bytes32(bytes20(self)),
            _currencyId,
            currencyPayout,
            firstTrancheTokenPayout + secondTrancheTokenPayout,
            0
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
        centrifugeChain.updateTrancheTokenPrice(poolId, trancheId, currencyId, 1010101010101010101);

        // invest
        uint256 investmentAmount = 100000000; // 100 * 10**6
        centrifugeChain.updateMember(poolId, trancheId, self, type(uint64).max);
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
        centrifugeChain.isExecutedCollectInvest(
            poolId, trancheId, bytes32(bytes20(self)), _currencyId, currencyPayout, trancheTokenPayout, 0
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
        centrifugeChain.updateTrancheTokenPrice(poolId, trancheId, currencyId, 1010101010101010101);

        // invest
        uint256 investmentAmount = 100000000000000000000; // 100 * 10**18
        centrifugeChain.updateMember(poolId, trancheId, self, type(uint64).max);
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
        centrifugeChain.isExecutedCollectInvest(
            poolId, trancheId, bytes32(bytes20(self)), _currencyId, currencyPayout, trancheTokenPayout, 0
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
        centrifugeChain.updateTrancheTokenPrice(poolId, trancheId, currencyId, 1000000);

        // invest
        uint256 investmentAmount = 100000000; // 100 * 10**6
        centrifugeChain.updateMember(poolId, trancheId, self, type(uint64).max);
        currency.approve(address(investmentManager), investmentAmount);
        currency.mint(self, investmentAmount);
        lPool.requestDeposit(investmentAmount, self);

        // trigger executed collectInvest at a price of 1.0
        uint128 _currencyId = poolManager.currencyAddressToId(address(currency)); // retrieve currencyId
        uint128 trancheTokenPayout = 100000000000000000000; // 100 * 10**18
        centrifugeChain.isExecutedCollectInvest(
            poolId, trancheId, bytes32(bytes20(self)), _currencyId, uint128(investmentAmount), trancheTokenPayout, 0
        );
        lPool.mint(trancheTokenPayout, self);

        // assert share/asset conversion
        assertEq(lPool.latestPrice(), 1000000000000000000);
        assertEq(lPool.totalSupply(), 100000000000000000000);
        assertEq(lPool.totalAssets(), 100000000);
        assertEq(lPool.convertToShares(100000000), 100000000000000000000); // tranche tokens have 12 more decimals than assets
        assertEq(lPool.convertToAssets(lPool.convertToShares(100000000000000000000)), 100000000000000000000);

        // assert share/asset conversion after price update
        centrifugeChain.updateTrancheTokenPrice(poolId, trancheId, currencyId, 1200000000000000000);

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
        centrifugeChain.updateTrancheTokenPrice(poolId, trancheId, currencyId, 1000000);

        // invest
        uint256 investmentAmount = 100000000000000000000; // 100 * 10**18
        centrifugeChain.updateMember(poolId, trancheId, self, type(uint64).max);
        currency.approve(address(investmentManager), investmentAmount);
        currency.mint(self, investmentAmount);
        lPool.requestDeposit(investmentAmount, self);

        // trigger executed collectInvest at a price of 1.0
        uint128 _currencyId = poolManager.currencyAddressToId(address(currency)); // retrieve currencyId
        uint128 trancheTokenPayout = 100000000; // 100 * 10**6
        centrifugeChain.isExecutedCollectInvest(
            poolId, trancheId, bytes32(bytes20(self)), _currencyId, uint128(investmentAmount), trancheTokenPayout, 0
        );
        lPool.mint(trancheTokenPayout, self);

        // assert share/asset conversion
        assertEq(lPool.latestPrice(), 1000000000000000000);
        assertEq(lPool.totalSupply(), 100000000);
        assertEq(lPool.totalAssets(), 100000000000000000000);
        assertEq(lPool.convertToShares(100000000000000000000), 100000000); // tranche tokens have 12 less decimals than assets
        assertEq(lPool.convertToAssets(lPool.convertToShares(100000000000000000000)), 100000000000000000000);

        // assert share/asset conversion after price update
        centrifugeChain.updateTrancheTokenPrice(poolId, trancheId, currencyId, 1200000000000000000);

        assertEq(lPool.latestPrice(), 1200000000000000000);
        assertEq(lPool.totalAssets(), 120000000000000000000);
        assertEq(lPool.convertToShares(120000000000000000000), 100000000); // tranche tokens have 12 less decimals than assets
        assertEq(lPool.convertToAssets(lPool.convertToShares(120000000000000000000)), 120000000000000000000);
    }

    function testCancelDepositOrder(uint256 amount) public {
        amount = uint128(bound(amount, 2, MAX_UINT128));

        uint128 price = 2 * 10 ** 27;
        address lPool_ = deploySimplePool();
        LiquidityPool lPool = LiquidityPool(lPool_);
        centrifugeChain.updateTrancheTokenPrice(lPool.poolId(), lPool.trancheId(), defaultCurrencyId, price);
        erc20.mint(self, amount);
        erc20.approve(address(investmentManager), amount); // add allowance
        centrifugeChain.updateMember(lPool.poolId(), lPool.trancheId(), self, type(uint64).max);

        lPool.requestDeposit(amount, self);

        assertEq(erc20.balanceOf(address(escrow)), amount);
        assertEq(erc20.balanceOf(address(self)), 0);

        // check message was send out to centchain
        lPool.cancelDepositRequest(self);
        bytes memory cancelOrderMessage = Messages.formatCancelInvestOrder(
            lPool.poolId(), lPool.trancheId(), _addressToBytes32(self), defaultCurrencyId
        );
        assertEq(cancelOrderMessage, router.values_bytes("send"));

        centrifugeChain.isExecutedDecreaseInvestOrder(
            lPool.poolId(), lPool.trancheId(), _addressToBytes32(self), defaultCurrencyId, uint128(amount), 0
        );
        assertEq(erc20.balanceOf(address(escrow)), 0);
        assertEq(erc20.balanceOf(address(userEscrow)), amount);
        assertEq(erc20.balanceOf(self), 0);
        assertEq(lPool.maxRedeem(self), amount);
        assertEq(lPool.maxWithdraw(self), amount);
    }

    function testDepositMint(uint256 amount) public {
        amount = uint128(bound(amount, 2, MAX_UINT128));

        uint128 price = 2 * 10 ** 27;

        address lPool_ = deploySimplePool();
        LiquidityPool lPool = LiquidityPool(lPool_);
        centrifugeChain.updateTrancheTokenPrice(lPool.poolId(), lPool.trancheId(), defaultCurrencyId, price);

        erc20.mint(self, amount);

        // will fail - user not member: can not receive trancheToken
        vm.expectRevert(bytes("InvestmentManager/transfer-not-allowed"));
        lPool.requestDeposit(amount, self);
        centrifugeChain.updateMember(lPool.poolId(), lPool.trancheId(), self, type(uint64).max); // add user as member

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
        assertEq(lPool.userDepositRequest(self), amount);

        // trigger executed collectInvest
        uint128 _currencyId = poolManager.currencyAddressToId(address(erc20)); // retrieve currencyId
        uint128 trancheTokensPayout = uint128(amount * 10 ** 27 / price); // trancheTokenPrice = 2$
        assertApproxEqAbs(trancheTokensPayout, amount / 2, 2);
        centrifugeChain.isExecutedCollectInvest(
            lPool.poolId(),
            lPool.trancheId(),
            bytes32(bytes20(self)),
            _currencyId,
            uint128(amount),
            trancheTokensPayout,
            0
        );

        // assert deposit & mint values adjusted
        assertEq(lPool.maxMint(self), trancheTokensPayout); // max deposit
        assertEq(lPool.maxDeposit(self), amount); // max deposit
        assertEq(lPool.userDepositRequest(self), 0);
        // assert tranche tokens minted
        assertEq(lPool.balanceOf(address(escrow)), trancheTokensPayout);
        // assert conversions
        assertEq(lPool.previewDeposit(amount), trancheTokensPayout);
        assertApproxEqAbs(lPool.previewMint(trancheTokensPayout), amount, 1);

        // deposit 50% of the amount
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

    function testDepositMintToReceiver(uint256 amount, address receiver) public {
        amount = uint128(bound(amount, 2, MAX_UINT128));
        vm.assume(addressAssumption(receiver));

        uint128 price = 2 * 10 ** 27;
        address lPool_ = deploySimplePool();
        LiquidityPool lPool = LiquidityPool(lPool_);
        centrifugeChain.updateTrancheTokenPrice(lPool.poolId(), lPool.trancheId(), defaultCurrencyId, price);

        erc20.mint(self, amount);

        centrifugeChain.updateMember(lPool.poolId(), lPool.trancheId(), self, type(uint64).max); // add user as member
        erc20.approve(address(investmentManager), amount); // add allowance
        lPool.requestDeposit(amount, self);

        // trigger executed collectInvest
        uint128 _currencyId = poolManager.currencyAddressToId(address(erc20)); // retrieve currencyId
        uint128 trancheTokensPayout = uint128(amount * 10 ** 27 / price); // trancheTokenPrice = 2$
        assertApproxEqAbs(trancheTokensPayout, amount / 2, 2);
        centrifugeChain.isExecutedCollectInvest(
            lPool.poolId(),
            lPool.trancheId(),
            bytes32(bytes20(self)),
            _currencyId,
            uint128(amount),
            trancheTokensPayout,
            0
        );

        // assert deposit & mint values adjusted
        assertEq(lPool.maxMint(self), trancheTokensPayout); // max deposit
        assertEq(lPool.maxDeposit(self), amount); // max deposit
        // assert tranche tokens minted
        assertEq(lPool.balanceOf(address(escrow)), trancheTokensPayout);
        // assert conversions
        assertEq(lPool.previewDeposit(amount), trancheTokensPayout);
        assertApproxEqAbs(lPool.previewMint(trancheTokensPayout), amount, 1);

        // deposit 1/2 funds to receiver
        vm.expectRevert(bytes("RestrictionManager/destination-not-a-member"));
        lPool.deposit(amount / 2, receiver); // mint half the amount

        vm.expectRevert(bytes("RestrictionManager/destination-not-a-member"));
        lPool.mint(amount / 2, receiver); // mint half the amount

        centrifugeChain.updateMember(lPool.poolId(), lPool.trancheId(), receiver, type(uint64).max); // add receiver member

        // success
        lPool.deposit(amount / 2, receiver); // mint half the amount
        lPool.mint(lPool.maxMint(self), receiver); // mint half the amount

        assertApproxEqAbs(lPool.balanceOf(receiver), trancheTokensPayout, 1);
        assertApproxEqAbs(lPool.balanceOf(receiver), trancheTokensPayout, 1);
        assertApproxEqAbs(lPool.balanceOf(address(escrow)), 0, 1);
        assertApproxEqAbs(erc20.balanceOf(address(escrow)), amount, 1);
    }

    function testDepositWithPermitFR(uint256 amount, address random) public {
        amount = uint128(bound(amount, 2, MAX_UINT128));
        vm.assume(addressAssumption(random));

        // Use a wallet with a known private key so we can sign the permit message
        address investor = vm.addr(0xABCD);
        vm.prank(vm.addr(0xABCD));

        address lPool_ = deploySimplePool();
        LiquidityPool lPool = LiquidityPool(lPool_);
        erc20.mint(investor, amount);
        centrifugeChain.updateMember(lPool.poolId(), lPool.trancheId(), investor, type(uint64).max);

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

        vm.prank(random); // random fr permit
        erc20.permit(investor, address(investmentManager), amount, block.timestamp, v, r, s);

        // investor still able to requestDepositWithPermit
        lPool.requestDepositWithPermit(amount, investor, block.timestamp, v, r, s);

        // ensure funds are locked in escrow
        assertEq(erc20.balanceOf(address(escrow)), amount);
        assertEq(erc20.balanceOf(investor), 0);
    }

    function testRedeemWithPermitFR(uint256 amount, address random) public {
        amount = uint128(bound(amount, 2, MAX_UINT128));
        vm.assume(addressAssumption(random));

        // Use a wallet with a known private key so we can sign the permit message
        address investor = vm.addr(0xABCD);

        address lPool_ = deploySimplePool();
        LiquidityPool lPool = LiquidityPool(lPool_);
        deposit(lPool_, investor, amount); // deposit funds first

        TrancheToken trancheToken = TrancheToken(address(lPool.share()));

        // Sign permit for redeeming tranche tokens
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
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
                            amount,
                            0,
                            block.timestamp
                        )
                    )
                )
            )
        );

        vm.prank(random); // random fr permit
        trancheToken.permit(investor, address(investmentManager), amount, block.timestamp, v, r, s);

        // investor still able to requestDepositWithPermit
        lPool.requestRedeemWithPermit(amount, investor, block.timestamp, v, r, s);
        // ensure tokens are locked in escrow
        assertEq(trancheToken.balanceOf(address(escrow)), amount);
        assertEq(trancheToken.balanceOf(investor), 0);
    }

    function testDepositAndRedeemWithPermit(uint256 amount) public {
        amount = uint128(bound(amount, 2, MAX_UINT128));

        // Use a wallet with a known private key so we can sign the permit message
        address investor = vm.addr(0xABCD);
        vm.prank(vm.addr(0xABCD));

        address lPool_ = deploySimplePool();
        LiquidityPool lPool = LiquidityPool(lPool_);
        erc20.mint(investor, amount);
        centrifugeChain.updateMember(lPool.poolId(), lPool.trancheId(), investor, type(uint64).max);

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
        centrifugeChain.isExecutedCollectInvest(
            lPool.poolId(),
            lPool.trancheId(),
            bytes32(bytes20(investor)),
            poolManager.currencyAddressToId(address(erc20)),
            uint128(amount),
            uint128(amount),
            0
        );

        uint256 maxMint = lPool.maxMint(investor);
        vm.prank(vm.addr(0xABCD));
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

    function testRedeem(uint256 amount) public {
        amount = uint128(bound(amount, 2, MAX_UINT128));

        address lPool_ = deploySimplePool();
        LiquidityPool lPool = LiquidityPool(lPool_);
        deposit(lPool_, self, amount); // deposit funds first
        centrifugeChain.updateTrancheTokenPrice(lPool.poolId(), lPool.trancheId(), defaultCurrencyId, defaultPrice);

        // will fail - user did not give tranche token allowance to investmentManager
        vm.expectRevert(bytes("ERC20/insufficient-allowance"));
        lPool.requestRedeem(amount, self);
        lPool.approve(address(investmentManager), amount); // add allowance

        // success
        lPool.requestRedeem(amount, self);
        assertEq(lPool.balanceOf(address(escrow)), amount);
        assertEq(lPool.userRedeemRequest(self), amount);

        // fail: no tokens left
        lPool.approve(address(investmentManager), amount); // add allowance
        vm.expectRevert(bytes("ERC20/insufficient-balance"));
        lPool.requestRedeem(amount, self);

        // trigger executed collectRedeem
        uint128 _currencyId = poolManager.currencyAddressToId(address(erc20)); // retrieve currencyId
        uint128 currencyPayout = uint128(amount) / uint128(defaultPrice);
        centrifugeChain.isExecutedCollectRedeem(
            lPool.poolId(), lPool.trancheId(), bytes32(bytes20(self)), _currencyId, currencyPayout, uint128(amount), 0
        );

        // assert withdraw & redeem values adjusted
        assertEq(lPool.maxWithdraw(self), currencyPayout); // max deposit
        assertEq(lPool.maxRedeem(self), amount); // max deposit
        assertEq(lPool.userRedeemRequest(self), 0);
        assertEq(lPool.balanceOf(address(escrow)), 0);
        assertEq(erc20.balanceOf(address(userEscrow)), currencyPayout);
        // assert conversions
        assertEq(lPool.previewWithdraw(currencyPayout), amount);
        assertEq(lPool.previewRedeem(amount), currencyPayout);

        // success
        lPool.redeem(amount / 2, self, self); // redeem half the amount to own wallet

        // fail -> investor has no approval to receive funds
        vm.expectRevert(bytes("UserEscrow/receiver-has-no-allowance"));
        lPool.redeem(amount / 2, investor, self); // redeem half the amount to another wallet

        // fail -> receiver needs to have max approval
        erc20.approve(investor, lPool.maxRedeem(self));
        vm.expectRevert(bytes("UserEscrow/receiver-has-no-allowance"));
        lPool.redeem(amount / 2, investor, self); // redeem half the amount to investor wallet

        // success
        erc20.approve(investor, type(uint256).max);
        lPool.redeem(amount / 2, investor, self); // redeem half the amount to investor wallet

        assertEq(lPool.balanceOf(self), 0);
        assertTrue(lPool.balanceOf(address(escrow)) <= 1);
        assertTrue(erc20.balanceOf(address(userEscrow)) <= 1);

        assertApproxEqAbs(erc20.balanceOf(self), (amount / 2), 1);
        assertApproxEqAbs(erc20.balanceOf(investor), (amount / 2), 1);
        assertTrue(lPool.maxWithdraw(self) <= 1);
        assertTrue(lPool.maxRedeem(self) <= 1);
    }

    function testCancelRedeemOrder(uint256 amount) public {
        amount = uint128(bound(amount, 2, MAX_UINT128));

        address lPool_ = deploySimplePool();
        LiquidityPool lPool = LiquidityPool(lPool_);
        deposit(lPool_, self, amount); // deposit funds first

        lPool.approve(address(investmentManager), amount); // add allowance
        lPool.requestRedeem(amount, self);

        assertEq(lPool.balanceOf(address(escrow)), amount);
        assertEq(lPool.balanceOf(self), 0);

        // check message was send out to centchain
        lPool.cancelRedeemRequest(self);
        bytes memory cancelOrderMessage = Messages.formatCancelRedeemOrder(
            lPool.poolId(), lPool.trancheId(), _addressToBytes32(self), defaultCurrencyId
        );
        assertEq(cancelOrderMessage, router.values_bytes("send"));

        centrifugeChain.isExecutedDecreaseRedeemOrder(
            lPool.poolId(), lPool.trancheId(), _addressToBytes32(self), defaultCurrencyId, uint128(amount), 0
        );

        assertEq(lPool.balanceOf(address(escrow)), amount);
        assertEq(lPool.balanceOf(self), 0);
        assertEq(lPool.maxDeposit(self), amount);
        assertEq(lPool.maxMint(self), amount);
    }

    function testWithdraw(uint256 amount) public {
        amount = uint128(bound(amount, 2, MAX_UINT128));

        address lPool_ = deploySimplePool();
        LiquidityPool lPool = LiquidityPool(lPool_);

        deposit(lPool_, self, amount); // deposit funds first
        centrifugeChain.updateTrancheTokenPrice(lPool.poolId(), lPool.trancheId(), defaultCurrencyId, defaultPrice);

        // will fail - user did not give tranche token allowance to investmentManager
        vm.expectRevert(bytes("SafeTransferLib/safe-transfer-from-failed"));
        lPool.requestDeposit(amount, self);
        lPool.approve(address(investmentManager), amount); // add allowance

        lPool.requestRedeem(amount, self);
        assertEq(lPool.balanceOf(address(escrow)), amount);
        assertEq(erc20.balanceOf(address(userEscrow)), 0);

        // trigger executed collectRedeem
        uint128 _currencyId = poolManager.currencyAddressToId(address(erc20)); // retrieve currencyId
        uint128 currencyPayout = uint128(amount) / defaultPrice;
        centrifugeChain.isExecutedCollectRedeem(
            lPool.poolId(), lPool.trancheId(), bytes32(bytes20(self)), _currencyId, currencyPayout, uint128(amount), 0
        );

        // assert withdraw & redeem values adjusted
        assertEq(lPool.maxWithdraw(self), currencyPayout); // max deposit
        assertEq(lPool.maxRedeem(self), amount); // max deposit
        assertEq(lPool.balanceOf(address(escrow)), 0);
        assertEq(erc20.balanceOf(address(userEscrow)), currencyPayout);

        lPool.withdraw(amount / 2, self, self); // withdraw half teh amount

        // fail -> investor has no approval to receive funds
        vm.expectRevert(bytes("UserEscrow/receiver-has-no-allowance"));
        lPool.withdraw(amount / 2, investor, self); // redeem half the amount to another wallet

        // fail -> receiver needs to have max approval
        erc20.approve(investor, lPool.maxWithdraw(self));
        vm.expectRevert(bytes("UserEscrow/receiver-has-no-allowance"));
        lPool.withdraw(amount / 2, investor, self); // redeem half the amount to investor wallet

        // success
        erc20.approve(investor, type(uint256).max);
        lPool.withdraw(amount / 2, investor, self); // redeem half the amount to investor wallet

        assertTrue(lPool.balanceOf(self) <= 1);
        assertTrue(erc20.balanceOf(address(userEscrow)) <= 1);
        assertApproxEqAbs(erc20.balanceOf(self), currencyPayout / 2, 1);
        assertApproxEqAbs(erc20.balanceOf(investor), currencyPayout / 2, 1);
        assertTrue(lPool.maxRedeem(self) <= 1);
        assertTrue(lPool.maxWithdraw(self) <= 1);
    }

    function testDecreaseDepositRequest(uint256 amount, uint256 decreaseAmount) public {
        amount = uint128(bound(amount, 2, MAX_UINT128));
        decreaseAmount = uint128(bound(decreaseAmount, 2, MAX_UINT128));
        vm.assume(amount > decreaseAmount);
        uint128 price = 2 * 10 ** 27;

        address lPool_ = deploySimplePool();
        LiquidityPool lPool = LiquidityPool(lPool_);
        centrifugeChain.updateTrancheTokenPrice(lPool.poolId(), lPool.trancheId(), defaultCurrencyId, price);

        erc20.mint(self, amount);
        centrifugeChain.updateMember(lPool.poolId(), lPool.trancheId(), self, type(uint64).max); // add user as member
        erc20.approve(address(investmentManager), amount); // add allowance
        lPool.requestDeposit(amount, self);

        assertEq(erc20.balanceOf(address(escrow)), amount);
        assertEq(erc20.balanceOf(self), 0);

        // decrease deposit request
        lPool.decreaseDepositRequest(decreaseAmount, self);
        centrifugeChain.isExecutedDecreaseInvestOrder(
            lPool.poolId(), lPool.trancheId(), bytes32(bytes20(self)), defaultCurrencyId, uint128(decreaseAmount), 0
        );

        assertEq(erc20.balanceOf(address(escrow)), amount - decreaseAmount);
        assertEq(erc20.balanceOf(address(userEscrow)), decreaseAmount);
        assertEq(erc20.balanceOf(self), 0);
        assertEq(lPool.maxWithdraw(self), decreaseAmount);
        assertEq(lPool.maxRedeem(self), decreaseAmount);
    }

    function testDecreaseRedeemRequest(uint256 amount, uint256 decreaseAmount) public {
        amount = uint128(bound(amount, 2, MAX_UINT128));
        decreaseAmount = uint128(bound(decreaseAmount, 2, MAX_UINT128));
        vm.assume(amount > decreaseAmount);

        address lPool_ = deploySimplePool();
        LiquidityPool lPool = LiquidityPool(lPool_);
        centrifugeChain.updateTrancheTokenPrice(lPool.poolId(), lPool.trancheId(), defaultCurrencyId, defaultPrice);
        deposit(lPool_, self, amount);
        lPool.approve(address(investmentManager), amount);
        lPool.requestRedeem(amount, self);

        assertEq(lPool.balanceOf(address(escrow)), amount);
        assertEq(lPool.balanceOf(self), 0);

        // decrease redeem request
        lPool.decreaseRedeemRequest(decreaseAmount, self);
        centrifugeChain.isExecutedDecreaseRedeemOrder(
            lPool.poolId(), lPool.trancheId(), bytes32(bytes20(self)), defaultCurrencyId, uint128(decreaseAmount), 0
        );

        assertEq(lPool.balanceOf(address(escrow)), amount);
        assertEq(lPool.balanceOf(self), 0);
        assertEq(lPool.maxDeposit(self), decreaseAmount);
        assertEq(lPool.maxMint(self), decreaseAmount);
    }

    function testTriggerIncreaseRedeemOrder(uint256 amount) public {
        amount = uint128(bound(amount, 2, MAX_UINT128));

        address lPool_ = deploySimplePool();
        LiquidityPool lPool = LiquidityPool(lPool_);
        deposit(lPool_, investor, amount); // deposit funds first
        uint256 investorBalanceBefore = erc20.balanceOf(investor);
        // Trigger request redeem of half the amount
        centrifugeChain.triggerIncreaseRedeemOrder(
            lPool.poolId(), lPool.trancheId(), investor, defaultCurrencyId, uint128(amount / 2)
        );

        assertApproxEqAbs(lPool.balanceOf(address(escrow)), amount / 2, 1);
        assertApproxEqAbs(lPool.balanceOf(investor), amount / 2, 1);

        centrifugeChain.isExecutedCollectRedeem(
            lPool.poolId(),
            lPool.trancheId(),
            bytes32(bytes20(investor)),
            defaultCurrencyId,
            uint128(amount / 2),
            uint128(amount / 2),
            uint128(amount / 2)
        );

        assertApproxEqAbs(lPool.balanceOf(address(escrow)), 0, 1);
        assertApproxEqAbs(erc20.balanceOf(address(userEscrow)), amount / 2, 1);

        vm.prank(investor);
        lPool.redeem(amount / 2, investor, investor);

        assertApproxEqAbs(erc20.balanceOf(investor), investorBalanceBefore + amount / 2, 1);
    }

    function testCollectDeposit(uint128 amount) public {
        amount = uint128(bound(amount, 2, MAX_UINT128));

        address lPool_ = deploySimplePool();
        LiquidityPool lPool = LiquidityPool(lPool_);
        centrifugeChain.updateTrancheTokenPrice(lPool.poolId(), lPool.trancheId(), defaultCurrencyId, defaultPrice);
        centrifugeChain.updateMember(lPool.poolId(), lPool.trancheId(), self, type(uint64).max);

        lPool.collectDeposit(self);
    }

    function testCollectRedeem(uint128 amount) public {
        amount = uint128(bound(amount, 2, MAX_UINT128));

        address lPool_ = deploySimplePool();
        LiquidityPool lPool = LiquidityPool(lPool_);
        centrifugeChain.allowInvestmentCurrency(lPool.poolId(), defaultCurrencyId);
        centrifugeChain.updateTrancheTokenPrice(lPool.poolId(), lPool.trancheId(), defaultCurrencyId, defaultPrice);

        centrifugeChain.updateMember(lPool.poolId(), lPool.trancheId(), self, type(uint64).max);
        lPool.collectRedeem(self);
    }

    // helpers
    function deposit(address _lPool, address investor, uint256 amount) public {
        LiquidityPool lPool = LiquidityPool(_lPool);
        erc20.mint(investor, amount);
        centrifugeChain.updateMember(lPool.poolId(), lPool.trancheId(), investor, type(uint64).max); // add user as member
        vm.prank(investor);
        erc20.approve(address(investmentManager), amount); // add allowance

        vm.prank(investor);
        lPool.requestDeposit(amount, investor);
        // trigger executed collectInvest
        uint128 currencyId = poolManager.currencyAddressToId(address(erc20)); // retrieve currencyId
        centrifugeChain.isExecutedCollectInvest(
            lPool.poolId(),
            lPool.trancheId(),
            bytes32(bytes20(investor)),
            currencyId,
            uint128(amount),
            uint128(amount),
            0
        );

        vm.prank(investor);
        lPool.deposit(amount, investor); // withdraw the amount
    }

    function amountAssumption(uint256 amount) public pure returns (bool) {
        return (amount > 1 && amount < MAX_UINT128);
    }

    function addressAssumption(address user) public view returns (bool) {
        return (user != address(0) && user != address(erc20) && user.code.length == 0);
    }
}
