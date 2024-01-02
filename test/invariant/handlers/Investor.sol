// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.18;

import {MockCentrifugeChain} from "test/mocks/MockCentrifugeChain.sol";
import {IERC7540} from "src/interfaces/IERC7540.sol";
import {BaseHandler} from "./BaseHandler.sol";
import {MathLib} from "src/libraries/MathLib.sol";

import "forge-std/Test.sol";

interface ERC20Like {
    function mint(address user, uint256 amount) external;
    function approve(address spender, uint256 value) external returns (bool);
    function balanceOf(address user) external view returns (uint256);
}

interface LiquidityPoolLike is IERC7540 {
    function decreaseDepositRequest(uint256 assets) external;
    function share() external view returns (address);
    function manager() external view returns (address);
}

contract InvestorHandler is BaseHandler {
    using MathLib for uint256;
    using MathLib for uint128;

    uint64 poolId;
    bytes16 trancheId;
    uint128 currencyId;

    ERC20Like immutable erc20;
    ERC20Like immutable trancheToken;
    LiquidityPoolLike immutable liquidityPool;
    MockCentrifugeChain immutable centrifugeChain;
    address immutable escrow;
    address immutable investmentManager;

    constructor(
        uint64 poolId_,
        bytes16 trancheId_,
        uint128 currencyId_,
        address _liquidityPool,
        address mockCentrifugeChain_,
        address erc20_,
        address escrow_,
        address state_
    ) BaseHandler(state_) {
        poolId = poolId_;
        trancheId = trancheId_;
        currencyId = currencyId_;

        liquidityPool = LiquidityPoolLike(_liquidityPool);
        centrifugeChain = MockCentrifugeChain(mockCentrifugeChain_);
        erc20 = ERC20Like(erc20_);
        trancheToken = ERC20Like(liquidityPool.share());
        escrow = escrow_;
        investmentManager = liquidityPool.manager();
    }

    // --- Investments ---
    function requestDeposit(uint256 investorSeed, uint128 amount) public useRandomInvestor(investorSeed) {
        // Don't allow total outstanding deposit requests > type(uint128).max
        uint256 amount_ = bound(
            amount,
            0,
            uint128(
                type(uint128).max - getVar(currentInvestor, "totalDepositRequested")
                    + getVar(currentInvestor, "totalCurrencyPaidOutOnInvest")
            )
        );
        if (amount == 0) return;

        vm.stopPrank();
        erc20.mint(currentInvestor, amount_);
        vm.startPrank(currentInvestor);

        erc20.approve(address(liquidityPool), amount_);

        // TODO: we should also set up tests where currentInvestor != operator
        liquidityPool.requestDeposit(amount_, currentInvestor, currentInvestor, "");

        increaseVar(currentInvestor, "totalDepositRequested", amount);
    }

    function decreaseDepositRequest(uint256 investorSeed, uint128 amount) public useRandomInvestor(investorSeed) {
        uint256 outstandingDepositRequest =
            getVar(currentInvestor, "totalDepositRequested") - getVar(currentInvestor, "totalCurrencyPaidOutOnInvest");

        uint256 amount_ = bound(amount, 0, outstandingDepositRequest);
        if (amount == 0) return;

        liquidityPool.decreaseDepositRequest(amount_);

        increaseVar(currentInvestor, "outstandingDecreaseDepositRequested", amount_);
        increaseVar(currentInvestor, "totalDecreaseDepositRequested", amount_);
    }

    function deposit(uint256 investorSeed, uint128 amount) public useRandomInvestor(investorSeed) {
        uint256 amount_ = bound(amount, 0, liquidityPool.maxDeposit(currentInvestor));
        if (amount_ == 0) return;

        liquidityPool.deposit(amount_, currentInvestor);
    }

    function mint(uint256 investorSeed, uint128 amount) public useRandomInvestor(investorSeed) {
        uint256 amount_ = bound(amount, 0, liquidityPool.maxMint(currentInvestor));
        if (amount_ == 0) return;

        liquidityPool.mint(amount_, currentInvestor);
    }

    // --- Redemptions ---
    function requestRedeem(uint256 investorSeed, uint128 amount) public useRandomInvestor(investorSeed) {
        uint256 amount_ = bound(
            amount,
            0,
            _min(
                // Don't allow total outstanding redeem requests > type(uint128).max
                uint128(
                    type(uint128).max - getVar(currentInvestor, "totalRedeemRequested")
                        + getVar(currentInvestor, "totalTrancheTokensPaidOutOnRedeem")
                ),
                // Cannot redeem more than current balance of TT
                trancheToken.balanceOf(currentInvestor)
            )
        );
        if (amount_ == 0) return;

        liquidityPool.requestRedeem(amount_, currentInvestor, currentInvestor, "");

        increaseVar(currentInvestor, "totalRedeemRequested", amount_);
    }

    function redeem(uint256 investorSeed, uint128 amount) public useRandomInvestor(investorSeed) {
        uint256 amount_ = bound(amount, 0, liquidityPool.maxRedeem(currentInvestor));
        if (amount_ == 0) return;

        uint256 preBalance = erc20.balanceOf(currentInvestor);
        liquidityPool.redeem(amount_, currentInvestor, currentInvestor);
        uint256 postBalance = erc20.balanceOf(currentInvestor);
        increaseVar(currentInvestor, "totalCurrencyReceived", postBalance - preBalance);
    }

    function withdraw(uint256 investorSeed, uint128 amount) public useRandomInvestor(investorSeed) {
        uint256 amount_ = bound(amount, 0, liquidityPool.maxWithdraw(currentInvestor));
        if (amount_ == 0) return;

        uint256 preBalance = erc20.balanceOf(currentInvestor);
        liquidityPool.withdraw(amount_, currentInvestor, currentInvestor);
        uint256 postBalance = erc20.balanceOf(currentInvestor);
        increaseVar(currentInvestor, "totalCurrencyReceived", postBalance - preBalance);
    }

    // --- Misc ---
    // TODO: should be moved to a separate contract
    function executedCollectInvest(uint256 investorSeed, uint256 fulfillmentRatio, uint256 fulfillmentPrice)
        public
        useRandomInvestor(investorSeed)
    {
        fulfillmentRatio = bound(fulfillmentRatio, 0, 1 * 10 ** 18); // 0% to 100%
        fulfillmentPrice = bound(fulfillmentPrice, 0, 2 * 10 ** 18); // 0.00 to 2.00

        // TODO: subtracting outstandingDecreaseDepositRequested here means that decrease requests
        // are never executed, which is not necessarily true
        uint256 outstandingDepositRequest =
            getVar(currentInvestor, "totalDepositRequested") - getVar(currentInvestor, "totalCurrencyPaidOutOnInvest");

        if (outstandingDepositRequest == 0) {
            return;
        }

        uint128 currencyPayout =
            uint128(outstandingDepositRequest.mulDiv(fulfillmentRatio, 1 * 10 ** 18, MathLib.Rounding.Down));
        uint128 trancheTokenPayout =
            uint128(currencyPayout.mulDiv(1 * 10 ** 18, fulfillmentPrice, MathLib.Rounding.Down));

        centrifugeChain.isExecutedCollectInvest(
            poolId,
            trancheId,
            bytes32(bytes20(currentInvestor)),
            currencyId,
            currencyPayout,
            trancheTokenPayout,
            uint128(outstandingDepositRequest - currencyPayout)
        );

        increaseVar(currentInvestor, "totalCurrencyPaidOutOnInvest", currencyPayout);
        increaseVar(currentInvestor, "totalTrancheTokensPaidOutOnInvest", trancheTokenPayout);
    }

    function executedCollectRedeem(uint256 investorSeed, uint256 fulfillmentRatio, uint256 fulfillmentPrice)
        public
        useRandomInvestor(investorSeed)
    {
        fulfillmentRatio = bound(fulfillmentRatio, 0, 1 * 10 ** 18); // 0% to 100%
        fulfillmentPrice = bound(fulfillmentPrice, 0, 2 * 10 ** 18); // 0.00 to 2.00

        uint256 outstandingRedeemRequest = getVar(currentInvestor, "totalRedeemRequested")
            - getVar(currentInvestor, "totalTrancheTokensPaidOutOnRedeem");

        if (outstandingRedeemRequest == 0) {
            return;
        }

        uint128 trancheTokenPayout =
            uint128(outstandingRedeemRequest.mulDiv(fulfillmentRatio, 1 * 10 ** 18, MathLib.Rounding.Down));
        uint128 currencyPayout =
            uint128(trancheTokenPayout.mulDiv(fulfillmentPrice, 1 * 10 ** 18, MathLib.Rounding.Down));

        centrifugeChain.isExecutedCollectRedeem(
            poolId,
            trancheId,
            bytes32(bytes20(currentInvestor)),
            currencyId,
            currencyPayout,
            trancheTokenPayout,
            uint128(outstandingRedeemRequest - currencyPayout)
        );

        increaseVar(currentInvestor, "totalTrancheTokensPaidOutOnRedeem", trancheTokenPayout);
        increaseVar(currentInvestor, "totalCurrencyPaidOutOnRedeem", currencyPayout);
    }
}
