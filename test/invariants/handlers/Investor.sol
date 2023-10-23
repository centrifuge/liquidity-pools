// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.18;

import {TestSetup} from "test/TestSetup.t.sol";
import {MockCentrifugeChain} from "test/mock/MockCentrifugeChain.sol";
import {MathLib} from "src/util/MathLib.sol";
import {IERC4626} from "src/interfaces/IERC4626.sol";
import {BaseHandler} from "./BaseHandler.sol";

interface ERC20Like {
    function mint(address user, uint256 amount) external;
    function approve(address spender, uint256 value) external returns (bool);
    function balanceOf(address user) external view returns (uint256);
}

interface LiquidityPoolLike is IERC4626 {
    function requestDeposit(uint256 assets) external;
    function requestRedeem(uint256 shares) external;
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

    struct InvestorState {
        uint256 totalDepositRequested;
        uint256 totalRedeemRequested;
        // For deposits we can just look at TT balance,
        // but for redemptions we need to bookkeep this
        // as we are also minting currency
        uint256 totalCurrencyReceived;
        uint256 totalTrancheTokensPaidOutOnInvest;
        uint256 totalCurrencyPaidOutOnInvest;
        uint256 totalCurrencyPaidOutOnRedeem;
        uint256 totalTrancheTokensPaidOutOnRedeem;
    }

    mapping(address investor => InvestorState) public investorState;

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
        InvestorState storage state = investorState[currentInvestor];

        // Don't allow total outstanding deposit requests > type(uint128).max
        uint256 amount_ = bound(
            amount, 0, uint128(type(uint128).max - state.totalDepositRequested + state.totalCurrencyPaidOutOnInvest)
        );
        if (amount == 0) return;

        vm.stopPrank();
        erc20.mint(currentInvestor, amount_);
        vm.startPrank(currentInvestor);

        erc20.approve(investmentManager, amount_);
        liquidityPool.requestDeposit(amount_);

        state.totalDepositRequested += amount_;
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
        InvestorState storage state = investorState[currentInvestor];

        uint256 amount_ = bound(
            amount,
            0,
            _min(
                // Don't allow total outstanding redeem requests > type(uint128).max
                uint128(type(uint128).max - state.totalRedeemRequested + state.totalTrancheTokensPaidOutOnRedeem),
                // Cannot redeem more than current balance of TT
                trancheToken.balanceOf(currentInvestor)
            )
        );
        if (amount_ == 0) return;

        liquidityPool.requestRedeem(amount_);

        state.totalRedeemRequested += amount_;
    }

    function redeem(uint256 investorSeed, uint128 amount) public useRandomInvestor(investorSeed) {
        InvestorState storage state = investorState[currentInvestor];

        uint256 amount_ = bound(amount, 0, liquidityPool.maxRedeem(currentInvestor));
        if (amount_ == 0) return;

        uint256 preBalance = erc20.balanceOf(currentInvestor);
        liquidityPool.redeem(amount_, currentInvestor, currentInvestor);
        uint256 postBalance = erc20.balanceOf(currentInvestor);
        state.totalCurrencyReceived += postBalance - preBalance;
    }

    function withdraw(uint256 investorSeed, uint128 amount) public useRandomInvestor(investorSeed) {
        InvestorState storage state = investorState[currentInvestor];

        uint256 amount_ = bound(amount, 0, liquidityPool.maxWithdraw(currentInvestor));
        if (amount_ == 0) return;

        uint256 preBalance = erc20.balanceOf(currentInvestor);
        liquidityPool.withdraw(amount_, currentInvestor, currentInvestor);
        uint256 postBalance = erc20.balanceOf(currentInvestor);
        state.totalCurrencyReceived += postBalance - preBalance;
    }

    // --- Misc ---
    // TODO: should be moved to a separate contract
    function executedCollectInvest(uint256 investorSeed, uint256 fulfillmentRatio, uint256 fulfillmentPrice)
        public
        useRandomInvestor(investorSeed)
    {
        InvestorState storage state = investorState[currentInvestor];

        fulfillmentRatio = bound(fulfillmentRatio, 0, 1 * 10 ** 18); // 0% to 100%
        fulfillmentPrice = bound(fulfillmentPrice, 0, 2 * 10 ** 18); // 0.00 to 2.00

        uint256 outstandingDepositRequest = state.totalDepositRequested - state.totalCurrencyPaidOutOnInvest;

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

        state.totalCurrencyPaidOutOnInvest += currencyPayout;
        state.totalTrancheTokensPaidOutOnInvest += trancheTokenPayout;
    }

    function executedCollectRedeem(uint256 investorSeed, uint256 fulfillmentRatio, uint256 fulfillmentPrice)
        public
        useRandomInvestor(investorSeed)
    {
        InvestorState storage state = investorState[currentInvestor];

        fulfillmentRatio = bound(fulfillmentRatio, 0, 1 * 10 ** 18); // 0% to 100%
        fulfillmentPrice = bound(fulfillmentPrice, 0, 2 * 10 ** 18); // 0.00 to 2.00

        uint256 outstandingRedeemRequest = state.totalRedeemRequested - state.totalTrancheTokensPaidOutOnRedeem;

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

        state.totalTrancheTokensPaidOutOnRedeem += trancheTokenPayout;
        state.totalCurrencyPaidOutOnRedeem += currencyPayout;
    }
}
