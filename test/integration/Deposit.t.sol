// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import "./../TestSetup.t.sol";

contract DepositTest is TestSetup {
    function testDepositMint(uint256 amount) public {
        // If lower than 4 or odd, rounding down can lead to not receiving any tokens
        amount = uint128(bound(amount, 4, MAX_UINT128));
        vm.assume(amount % 2 == 0);

        uint128 price = 2 * 10 ** 18;

        address lPool_ = deploySimplePool();
        LiquidityPool lPool = LiquidityPool(lPool_);
        centrifugeChain.updateTrancheTokenPrice(
            lPool.poolId(), lPool.trancheId(), defaultCurrencyId, price, uint64(block.timestamp)
        );

        erc20.mint(self, amount);

        // will fail - user not member: can not receive trancheToken
        vm.expectRevert(bytes("InvestmentManager/sender-is-restricted"));
        lPool.requestDeposit(amount, self);

        centrifugeChain.updateMember(lPool.poolId(), lPool.trancheId(), self, type(uint64).max); // add user as member

        // will fail - user did not give currency allowance to liquidity pool
        vm.expectRevert(bytes("SafeTransferLib/safe-transfer-from-failed"));
        lPool.requestDeposit(amount, self);

        // success
        erc20.approve(lPool_, amount);
        lPool.requestDeposit(amount, self);

        // fail: no currency left
        vm.expectRevert(bytes("LiquidityPool/insufficient-balance"));
        lPool.requestDeposit(amount, self);

        // ensure funds are locked in escrow
        assertEq(erc20.balanceOf(address(escrow)), amount);
        assertEq(erc20.balanceOf(self), 0);
        assertEq(lPool.pendingDepositRequest(self), amount);

        // trigger executed collectInvest
        uint128 _currencyId = poolManager.currencyAddressToId(address(erc20)); // retrieve currencyId
        uint128 trancheTokensPayout = uint128((amount * 10 ** 18) / price); // trancheTokenPrice = 2$
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
        assertEq(lPool.maxMint(self), trancheTokensPayout);
        assertApproxEqAbs(lPool.maxDeposit(self), amount, 1);
        assertEq(lPool.pendingDepositRequest(self), 0);
        // assert tranche tokens minted
        assertEq(lPool.balanceOf(address(escrow)), trancheTokensPayout);

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

    function testPartialExecutions(uint64 poolId, bytes16 trancheId, uint128 currencyId) public {
        vm.assume(currencyId > 0);

        uint8 TRANCHE_TOKEN_DECIMALS = 18; // Like DAI
        uint8 INVESTMENT_CURRENCY_DECIMALS = 6; // 6, like USDC

        ERC20 currency = _newErc20("Currency", "CR", INVESTMENT_CURRENCY_DECIMALS);
        address lPool_ = deployLiquidityPool(
            poolId, TRANCHE_TOKEN_DECIMALS, defaultRestrictionSet, "", "", trancheId, currencyId, address(currency)
        );
        LiquidityPool lPool = LiquidityPool(lPool_);
        centrifugeChain.updateTrancheTokenPrice(
            poolId, trancheId, currencyId, 1000000000000000000, uint64(block.timestamp)
        );

        // invest
        uint256 investmentAmount = 100000000; // 100 * 10**6
        centrifugeChain.updateMember(poolId, trancheId, self, type(uint64).max);
        currency.approve(lPool_, investmentAmount);
        currency.mint(self, investmentAmount);
        lPool.requestDeposit(investmentAmount, self);
        uint128 _currencyId = poolManager.currencyAddressToId(address(currency)); // retrieve currencyId

        // first trigger executed collectInvest of the first 50% at a price of 1.4
        uint128 currencyPayout = 50000000; // 50 * 10**6
        uint128 firstTrancheTokenPayout = 35714285714285714285; // 50 * 10**18 / 1.4, rounded down
        centrifugeChain.isExecutedCollectInvest(
            poolId,
            trancheId,
            bytes32(bytes20(self)),
            _currencyId,
            currencyPayout,
            firstTrancheTokenPayout,
            currencyPayout
        );

        (, uint256 depositPrice,,,,,) = investmentManager.investments(address(lPool), self);
        assertEq(depositPrice, 1400000000000000000);

        // second trigger executed collectInvest of the second 50% at a price of 1.2
        uint128 secondTrancheTokenPayout = 41666666666666666666; // 50 * 10**18 / 1.2, rounded down
        centrifugeChain.isExecutedCollectInvest(
            poolId, trancheId, bytes32(bytes20(self)), _currencyId, currencyPayout, secondTrancheTokenPayout, 0
        );

        (, depositPrice,,,,,) = investmentManager.investments(address(lPool), self);
        assertEq(depositPrice, 1292307679384615384);

        // assert deposit & mint values adjusted
        assertApproxEqAbs(lPool.maxDeposit(self), currencyPayout * 2, 2);
        assertEq(lPool.maxMint(self), firstTrancheTokenPayout + secondTrancheTokenPayout);

        // collect the tranche tokens
        lPool.mint(firstTrancheTokenPayout + secondTrancheTokenPayout, self);
        assertEq(lPool.balanceOf(self), firstTrancheTokenPayout + secondTrancheTokenPayout);
    }

    function testDepositFairRounding(uint256 totalAmount, uint256 tokenAmount) public {
        totalAmount = bound(totalAmount, 1 * 10 ** 6, type(uint128).max / 10 ** 12);
        tokenAmount = bound(tokenAmount, 1 * 10 ** 6, type(uint128).max / 10 ** 12);

        //Deploy a pool
        LiquidityPool lPool = LiquidityPool(deploySimplePool());
        TrancheTokenLike trancheToken = TrancheTokenLike(address(lPool.share()));

        root.relyContract(address(trancheToken), self);
        trancheToken.mint(address(escrow), type(uint128).max); // mint buffer to the escrow. Mock funds from other users

        // fund user & request deposit
        centrifugeChain.updateMember(lPool.poolId(), lPool.trancheId(), self, uint64(block.timestamp));
        erc20.mint(self, totalAmount);
        erc20.approve(address(lPool), totalAmount);
        lPool.requestDeposit(totalAmount, self);

        // Ensure funds were locked in escrow
        assertEq(erc20.balanceOf(address(escrow)), totalAmount);
        assertEq(erc20.balanceOf(self), 0);

        // Gateway returns randomly generated values for amount of tranche tokens and currency
        centrifugeChain.isExecutedCollectInvest(
            lPool.poolId(),
            lPool.trancheId(),
            bytes32(bytes20(self)),
            defaultCurrencyId,
            uint128(totalAmount),
            uint128(tokenAmount),
            0
        );

        // user claims multiple partial deposits
        vm.assume(lPool.maxDeposit(self) > 0);
        assertEq(erc20.balanceOf(self), 0);
        while (lPool.maxDeposit(self) > 0) {
            uint256 randomDeposit = random(lPool.maxDeposit(self), 1);

            try lPool.deposit(randomDeposit, self) {
                if (lPool.maxDeposit(self) == 0 && lPool.maxMint(self) > 0) {
                    // If you cannot deposit anymore because the 1 wei remaining is rounded down,
                    // you should mint the remainder instead.
                    lPool.mint(lPool.maxMint(self), self);
                    break;
                }
            } catch {
                // If you cannot deposit anymore because the 1 wei remaining is rounded down,
                // you should mint the remainder instead.
                lPool.mint(lPool.maxMint(self), self);
                break;
            }
        }

        assertEq(lPool.maxDeposit(self), 0);
        assertApproxEqAbs(lPool.balanceOf(self), tokenAmount, 1);
    }

    function testMintFairRounding(uint256 totalAmount, uint256 tokenAmount) public {
        totalAmount = bound(totalAmount, 1 * 10 ** 6, type(uint128).max / 10 ** 12);
        tokenAmount = bound(tokenAmount, 1 * 10 ** 6, type(uint128).max / 10 ** 12);

        //Deploy a pool
        LiquidityPool lPool = LiquidityPool(deploySimplePool());
        TrancheTokenLike trancheToken = TrancheTokenLike(address(lPool.share()));

        root.relyContract(address(trancheToken), self);
        trancheToken.mint(address(escrow), type(uint128).max); // mint buffer to the escrow. Mock funds from other users

        // fund user & request deposit
        centrifugeChain.updateMember(lPool.poolId(), lPool.trancheId(), self, uint64(block.timestamp));
        erc20.mint(self, totalAmount);
        erc20.approve(address(lPool), totalAmount);
        lPool.requestDeposit(totalAmount, self);

        // Ensure funds were locked in escrow
        assertEq(erc20.balanceOf(address(escrow)), totalAmount);
        assertEq(erc20.balanceOf(self), 0);

        // Gateway returns randomly generated values for amount of tranche tokens and currency
        centrifugeChain.isExecutedCollectInvest(
            lPool.poolId(),
            lPool.trancheId(),
            bytes32(bytes20(self)),
            defaultCurrencyId,
            uint128(totalAmount),
            uint128(tokenAmount),
            0
        );

        // user claims multiple partial mints
        uint256 i = 0;
        while (lPool.maxMint(self) > 0) {
            uint256 randomMint = random(lPool.maxMint(self), i);
            try lPool.mint(randomMint, self) {
                i++;
            } catch {
                break;
            }
        }

        assertEq(lPool.maxMint(self), 0);
        assertLe(lPool.balanceOf(self), tokenAmount);
    }

    function testDepositMintToReceiver(uint256 amount) public {
        // If lower than 4 or odd, rounding down can lead to not receiving any tokens
        amount = uint128(bound(amount, 4, MAX_UINT128));
        vm.assume(amount % 2 == 0);

        uint128 price = 2 * 10 ** 18;
        address lPool_ = deploySimplePool();
        address receiver = makeAddr("receiver");
        LiquidityPool lPool = LiquidityPool(lPool_);

        centrifugeChain.updateTrancheTokenPrice(
            lPool.poolId(), lPool.trancheId(), defaultCurrencyId, price, uint64(block.timestamp)
        );

        erc20.mint(self, amount);

        centrifugeChain.updateMember(lPool.poolId(), lPool.trancheId(), self, type(uint64).max); // add user as member
        erc20.approve(lPool_, amount); // add allowance
        lPool.requestDeposit(amount, self);

        // trigger executed collectInvest
        uint128 _currencyId = poolManager.currencyAddressToId(address(erc20)); // retrieve currencyId
        uint128 trancheTokensPayout = uint128(amount * 10 ** 18 / price); // trancheTokenPrice = 2$
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

        // deposit 1/2 funds to receiver
        vm.expectRevert(bytes("RestrictionManager/destination-not-a-member"));
        lPool.deposit(amount / 2, receiver); // mint half the amount

        vm.expectRevert(bytes("RestrictionManager/destination-not-a-member"));
        lPool.mint(amount / 2, receiver); // mint half the amount

        centrifugeChain.updateMember(lPool.poolId(), lPool.trancheId(), receiver, type(uint64).max); // add receiver
            // member

        // success
        lPool.deposit(amount / 2, receiver); // mint half the amount
        lPool.mint(lPool.maxMint(self), receiver); // mint half the amount

        assertApproxEqAbs(lPool.balanceOf(receiver), trancheTokensPayout, 1);
        assertApproxEqAbs(lPool.balanceOf(receiver), trancheTokensPayout, 1);
        assertApproxEqAbs(lPool.balanceOf(address(escrow)), 0, 1);
        assertApproxEqAbs(erc20.balanceOf(address(escrow)), amount, 1);
    }

    function testDepositWithPermitFR(uint256 amount) public {
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
                    keccak256(abi.encode(erc20.PERMIT_TYPEHASH(), investor, lPool_, amount, 0, block.timestamp))
                )
            )
        );

        vm.startPrank(randomUser); // random fr permit
        erc20.permit(investor, lPool_, amount, block.timestamp, v, r, s);
        // frontrunnign not possible
        centrifugeChain.updateMember(lPool.poolId(), lPool.trancheId(), randomUser, type(uint64).max);
        vm.expectRevert(bytes("SafeTransferLib/safe-transfer-from-failed"));
        lPool.requestDepositWithPermit((amount), block.timestamp, v, r, s);
        vm.stopPrank();

        // investor still able to requestDepositWithPermit
        vm.prank(vm.addr(0xABCD));
        lPool.requestDepositWithPermit(amount, block.timestamp, v, r, s);

        // ensure funds are locked in escrow
        assertEq(erc20.balanceOf(address(escrow)), amount);
        assertEq(erc20.balanceOf(investor), 0);
    }

    function testDepositWithPermit(uint256 amount) public {
        amount = uint128(bound(amount, 2, MAX_UINT128));

        // Use a wallet with a known private key so we can sign the permit message
        address investor = vm.addr(0xABCD);
        vm.prank(investor);

        address lPool_ = deploySimplePool();
        LiquidityPool lPool = LiquidityPool(lPool_);
        erc20.mint(investor, amount);
        centrifugeChain.updateMember(lPool.poolId(), lPool.trancheId(), investor, type(uint64).max);
        centrifugeChain.updateMember(lPool.poolId(), lPool.trancheId(), address(this), type(uint64).max);

        // Sign permit for depositing investment currency
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            0xABCD,
            keccak256(
                abi.encodePacked(
                    "\x19\x01",
                    erc20.DOMAIN_SEPARATOR(),
                    keccak256(abi.encode(erc20.PERMIT_TYPEHASH(), investor, lPool_, amount, 0, block.timestamp))
                )
            )
        );

        // premit functions can only be executed by the owner
        vm.expectRevert(bytes("SafeTransferLib/safe-transfer-from-failed"));
        lPool.requestDepositWithPermit(amount, block.timestamp, v, r, s);
        vm.prank(vm.addr(0xABCD));
        lPool.requestDepositWithPermit(amount, block.timestamp, v, r, s);

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
    }

    function testDepositAndRedeemPrecision(uint64 poolId, bytes16 trancheId, uint128 currencyId) public {
        vm.assume(currencyId > 0);

        uint8 TRANCHE_TOKEN_DECIMALS = 18; // Like DAI
        uint8 INVESTMENT_CURRENCY_DECIMALS = 6; // 6, like USDC

        ERC20 currency = _newErc20("Currency", "CR", INVESTMENT_CURRENCY_DECIMALS);
        address lPool_ = deployLiquidityPool(
            poolId, TRANCHE_TOKEN_DECIMALS, defaultRestrictionSet, "", "", trancheId, currencyId, address(currency)
        );
        LiquidityPool lPool = LiquidityPool(lPool_);
        centrifugeChain.updateTrancheTokenPrice(
            poolId, trancheId, currencyId, 1000000000000000000, uint64(block.timestamp)
        );

        // invest
        uint256 investmentAmount = 100000000; // 100 * 10**6
        centrifugeChain.updateMember(poolId, trancheId, self, type(uint64).max);
        currency.approve(lPool_, investmentAmount);
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
        assertApproxEqAbs(lPool.maxDeposit(self), currencyPayout, 1);
        assertEq(lPool.maxMint(self), firstTrancheTokenPayout);

        // deposit price should be ~1.2*10**18
        (, uint256 depositPrice,,,,,) = investmentManager.investments(address(lPool), self);
        assertEq(depositPrice, 1200000000000000000);

        // trigger executed collectInvest of the second 50% at a price of 1.4
        currencyPayout = 50000000; // 50 * 10**6
        uint128 secondTrancheTokenPayout = 35714285714285714285; // 50 * 10**18 / 1.4, rounded down
        centrifugeChain.isExecutedCollectInvest(
            poolId, trancheId, bytes32(bytes20(self)), _currencyId, currencyPayout, secondTrancheTokenPayout, 0
        );

        // collect the tranche tokens
        lPool.mint(firstTrancheTokenPayout + secondTrancheTokenPayout, self);
        assertEq(lPool.balanceOf(self), firstTrancheTokenPayout + secondTrancheTokenPayout);

        // redeem
        lPool.requestRedeem(firstTrancheTokenPayout + secondTrancheTokenPayout, address(this), address(this));

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
        (,,, uint256 redeemPrice,,,) = investmentManager.investments(address(lPool), self);
        assertEq(redeemPrice, 1492615384615384615);

        // collect the currency
        lPool.withdraw(currencyPayout, self, self);
        assertEq(currency.balanceOf(self), currencyPayout);
    }

    function testDepositAndRedeemPrecisionWithInverseDecimals(uint64 poolId, bytes16 trancheId, uint128 currencyId)
        public
    {
        vm.assume(currencyId > 0);

        // uint8 TRANCHE_TOKEN_DECIMALS = 6; // Like DAI
        // uint8 INVESTMENT_CURRENCY_DECIMALS = 18; // 18, like USDC

        ERC20 currency = _newErc20("Currency", "CR", 18);
        address lPool_ =
            deployLiquidityPool(poolId, 6, defaultRestrictionSet, "", "", trancheId, currencyId, address(currency));
        LiquidityPool lPool = LiquidityPool(lPool_);
        centrifugeChain.updateTrancheTokenPrice(
            poolId, trancheId, currencyId, 1000000000000000000000000000, uint64(block.timestamp)
        );

        // invest
        uint256 investmentAmount = 100000000000000000000; // 100 * 10**18
        centrifugeChain.updateMember(poolId, trancheId, self, type(uint64).max);
        currency.approve(lPool_, investmentAmount);
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
        assertApproxEqAbs(lPool.maxDeposit(self), currencyPayout, 10);
        assertEq(lPool.maxMint(self), firstTrancheTokenPayout);

        // deposit price should be ~1.2*10**18
        (, uint256 depositPrice,,,,,) = investmentManager.investments(address(lPool), self);
        assertEq(depositPrice, 1200000019200000307);

        // trigger executed collectInvest of the second 50% at a price of 1.4
        currencyPayout = 50000000000000000000; // 50 * 10**18
        uint128 secondTrancheTokenPayout = 35714285; // 50 * 10**6 / 1.4, rounded down
        centrifugeChain.isExecutedCollectInvest(
            poolId, trancheId, bytes32(bytes20(self)), _currencyId, currencyPayout, secondTrancheTokenPayout, 0
        );

        // collect the tranche tokens
        lPool.mint(firstTrancheTokenPayout + secondTrancheTokenPayout, self);
        assertEq(lPool.balanceOf(self), firstTrancheTokenPayout + secondTrancheTokenPayout);

        // redeem
        lPool.requestRedeem(firstTrancheTokenPayout + secondTrancheTokenPayout, address(this), address(this));

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
        (,,, uint256 redeemPrice,,,) = investmentManager.investments(address(lPool), self);
        assertEq(redeemPrice, 1492615411252828877);

        // collect the currency
        lPool.withdraw(currencyPayout, self, self);
        assertEq(currency.balanceOf(self), currencyPayout);
    }

    // Test that assumes the swap from usdc (investment currency) to dai (pool currency) has a cost of 1%
    function testDepositAndRedeemPrecisionWithSlippage(uint64 poolId, bytes16 trancheId, uint128 currencyId) public {
        vm.assume(currencyId > 0);

        uint8 INVESTMENT_CURRENCY_DECIMALS = 6; // 6, like USDC
        uint8 TRANCHE_TOKEN_DECIMALS = 18; // Like DAI

        ERC20 currency = _newErc20("Currency", "CR", INVESTMENT_CURRENCY_DECIMALS);
        address lPool_ = deployLiquidityPool(
            poolId, TRANCHE_TOKEN_DECIMALS, defaultRestrictionSet, "", "", trancheId, currencyId, address(currency)
        );
        LiquidityPool lPool = LiquidityPool(lPool_);

        // price = (100*10**18) /  (99 * 10**18) = 101.010101 * 10**18
        centrifugeChain.updateTrancheTokenPrice(
            poolId, trancheId, currencyId, 1010101010101010101, uint64(block.timestamp)
        );

        // invest
        uint256 investmentAmount = 100000000; // 100 * 10**6
        centrifugeChain.updateMember(poolId, trancheId, self, type(uint64).max);
        currency.approve(lPool_, investmentAmount);
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
        centrifugeChain.updateTrancheTokenPrice(
            poolId, trancheId, currencyId, 1200000000000000000, uint64(block.timestamp)
        );

        // assert deposit & mint values adjusted
        assertEq(lPool.maxDeposit(self), currencyPayout);
        assertEq(lPool.maxMint(self), trancheTokenPayout);

        // lp price is set to the deposit price
        (, uint256 depositPrice,,,,,) = investmentManager.investments(address(lPool), self);
        assertEq(depositPrice, 1200000000000000000);
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
        address lPool_ = deployLiquidityPool(
            poolId, TRANCHE_TOKEN_DECIMALS, defaultRestrictionSet, "", "", trancheId, currencyId, address(currency)
        );
        LiquidityPool lPool = LiquidityPool(lPool_);

        // price = (100*10**18) /  (99 * 10**18) = 101.010101 * 10**18
        centrifugeChain.updateTrancheTokenPrice(
            poolId, trancheId, currencyId, 1010101010101010101, uint64(block.timestamp)
        );

        // invest
        uint256 investmentAmount = 100000000000000000000; // 100 * 10**18
        centrifugeChain.updateMember(poolId, trancheId, self, type(uint64).max);
        currency.approve(lPool_, investmentAmount);
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
        centrifugeChain.updateTrancheTokenPrice(
            poolId, trancheId, currencyId, 1200000000000000000, uint64(block.timestamp)
        );

        // assert deposit & mint values adjusted
        assertEq(lPool.maxDeposit(self), currencyPayout);
        assertEq(lPool.maxMint(self), trancheTokenPayout);

        // lp price is set to the deposit price
        (, uint256 depositPrice,,,,,) = investmentManager.investments(address(lPool), self);
        assertEq(depositPrice, 1200000000000000000);
    }

    function testDecreaseDepositPrecision(uint64 poolId, bytes16 trancheId, uint128 currencyId) public {
        vm.assume(currencyId > 0);

        uint8 TRANCHE_TOKEN_DECIMALS = 18; // Like DAI
        uint8 INVESTMENT_CURRENCY_DECIMALS = 6; // 6, like USDC

        ERC20 currency = _newErc20("Currency", "CR", INVESTMENT_CURRENCY_DECIMALS);
        address lPool_ = deployLiquidityPool(
            poolId, TRANCHE_TOKEN_DECIMALS, defaultRestrictionSet, "", "", trancheId, currencyId, address(currency)
        );
        LiquidityPool lPool = LiquidityPool(lPool_);
        centrifugeChain.updateTrancheTokenPrice(
            poolId, trancheId, currencyId, 1000000000000000000, uint64(block.timestamp)
        );

        // invest
        uint256 investmentAmount = 100000000; // 100 * 10**6
        centrifugeChain.updateMember(poolId, trancheId, self, type(uint64).max);
        currency.approve(lPool_, investmentAmount);
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
            uint128(investmentAmount) - currencyPayout
        );

        // assert deposit & mint values adjusted
        assertApproxEqAbs(lPool.maxDeposit(self), currencyPayout, 1);
        assertEq(lPool.maxMint(self), firstTrancheTokenPayout);

        // decrease the remaining 50%
        uint256 decreaseAmount = 50000000;
        lPool.decreaseDepositRequest(decreaseAmount);
        centrifugeChain.isExecutedDecreaseInvestOrder(
            poolId, trancheId, bytes32(bytes20(self)), _currencyId, uint128(decreaseAmount), 0
        );

        // deposit price should be ~1.2*10**18, redeem price should be 1.0*10**18
        (, uint256 depositPrice,, uint256 redeemPrice,,,) = investmentManager.investments(address(lPool), self);
        assertEq(depositPrice, 1200000000000000000);
        assertEq(redeemPrice, 1000000000000000000);
        assertEq(lPool.maxWithdraw(self), 50000000);
        assertEq(lPool.maxRedeem(self), 50000000000000000000);
    }

    function testDecreaseDepositRequest(uint256 amount, uint256 decreaseAmount) public {
        decreaseAmount = uint128(bound(decreaseAmount, 2, MAX_UINT128 - 1));
        amount = uint128(bound(amount, decreaseAmount + 1, MAX_UINT128)); // amount > decreaseAmount
        uint128 price = 2 * 10 ** 18;

        address lPool_ = deploySimplePool();
        LiquidityPool lPool = LiquidityPool(lPool_);
        centrifugeChain.updateTrancheTokenPrice(
            lPool.poolId(), lPool.trancheId(), defaultCurrencyId, price, uint64(block.timestamp)
        );

        erc20.mint(self, amount);
        centrifugeChain.updateMember(lPool.poolId(), lPool.trancheId(), self, type(uint64).max); // add user as member
        erc20.approve(lPool_, amount); // add allowance
        lPool.requestDeposit(amount, self);

        assertEq(erc20.balanceOf(address(escrow)), amount);
        assertEq(erc20.balanceOf(self), 0);

        // decrease deposit request
        lPool.decreaseDepositRequest(decreaseAmount);
        centrifugeChain.isExecutedDecreaseInvestOrder(
            lPool.poolId(), lPool.trancheId(), bytes32(bytes20(self)), defaultCurrencyId, uint128(decreaseAmount), 0
        );

        assertEq(erc20.balanceOf(address(escrow)), amount - decreaseAmount);
        assertEq(erc20.balanceOf(address(userEscrow)), decreaseAmount);
        assertEq(erc20.balanceOf(self), 0);
        assertEq(lPool.maxWithdraw(self), decreaseAmount);
        assertEq(lPool.maxRedeem(self), decreaseAmount);
    }

    function testCancelDepositOrder(uint256 amount) public {
        amount = uint128(bound(amount, 2, MAX_UINT128));

        uint128 price = 2 * 10 ** 18;
        address lPool_ = deploySimplePool();
        LiquidityPool lPool = LiquidityPool(lPool_);
        centrifugeChain.updateTrancheTokenPrice(
            lPool.poolId(), lPool.trancheId(), defaultCurrencyId, price, uint64(block.timestamp)
        );
        erc20.mint(self, amount);
        erc20.approve(lPool_, amount); // add allowance
        centrifugeChain.updateMember(lPool.poolId(), lPool.trancheId(), self, type(uint64).max);

        lPool.requestDeposit(amount, self);

        assertEq(erc20.balanceOf(address(escrow)), amount);
        assertEq(erc20.balanceOf(address(self)), 0);

        // check message was send out to centchain
        lPool.cancelDepositRequest();
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

    function partialDeposit(uint64 poolId, bytes16 trancheId, LiquidityPool lPool, ERC20 currency) public {
        uint256 investmentAmount = 100000000; // 100 * 10**6
        centrifugeChain.updateMember(poolId, trancheId, self, type(uint64).max);
        currency.approve(address(lPool), investmentAmount);
        currency.mint(self, investmentAmount);
        lPool.requestDeposit(investmentAmount, self);
        uint128 _currencyId = poolManager.currencyAddressToId(address(currency)); // retrieve currencyId

        // first trigger executed collectInvest of the first 50% at a price of 1.4
        uint128 currencyPayout = 50000000; // 50 * 10**6
        uint128 firstTrancheTokenPayout = 35714285714285714285; // 50 * 10**18 / 1.4, rounded down
        centrifugeChain.isExecutedCollectInvest(
            poolId, trancheId, bytes32(bytes20(self)), _currencyId, currencyPayout, firstTrancheTokenPayout, currencyPayout
        );
        
        (, uint256 depositPrice,,,,,) = investmentManager.investments(address(lPool), self);
        assertEq(depositPrice, 1400000000000000000);

        // second trigger executed collectInvest of the second 50% at a price of 1.2
        uint128 secondTrancheTokenPayout = 41666666666666666666; // 50 * 10**18 / 1.2, rounded down
        centrifugeChain.isExecutedCollectInvest(
            poolId,
            trancheId,
            bytes32(bytes20(self)),
            _currencyId,
            currencyPayout,
            secondTrancheTokenPayout,
            0
        );

        (, depositPrice,,,,,) = investmentManager.investments(address(lPool), self);
        assertEq(depositPrice, 1292307679384615384);

        // assert deposit & mint values adjusted
        assertApproxEqAbs(lPool.maxDeposit(self), currencyPayout * 2, 2);
        assertEq(lPool.maxMint(self), firstTrancheTokenPayout + secondTrancheTokenPayout);

        // collect the tranche tokens
        lPool.mint(firstTrancheTokenPayout + secondTrancheTokenPayout, self);
        assertEq(lPool.balanceOf(self), firstTrancheTokenPayout + secondTrancheTokenPayout);
    }
}
