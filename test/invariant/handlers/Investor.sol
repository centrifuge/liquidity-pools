// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.18;

import {MockCentrifugeChain} from "test/mocks/MockCentrifugeChain.sol";
import {MathLib} from "src/libraries/MathLib.sol";
import {IERC4626} from "src/interfaces/IERC7575.sol";

import "forge-std/Test.sol";

interface ERC20Like {
    function mint(address user, uint256 amount) external;
    function approve(address spender, uint256 value) external returns (bool);
    function balanceOf(address user) external view returns (uint256);
}

interface LiquidityPoolLike is IERC4626 {
    function requestDeposit(uint256 assets, address owner) external;
    function requestRedeem(uint256 shares, address owner) external;
    function share() external view returns (address);
    function manager() external view returns (address);
}

contract InvestorHandler is Test {
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

    uint256 public totalDepositRequested;
    uint256 public totalRedeemRequested;

    // For deposits we can just look at TT balance,
    // but for redemptions we need to bookkeep this
    // as we are also minting currency
    uint256 public totalCurrencyReceived;

    uint256 public totalTrancheTokensPaidOutOnInvest;
    uint256 public totalCurrencyPaidOutOnInvest;

    uint256 public totalCurrencyPaidOutOnRedeem;
    uint256 public totalTrancheTokensPaidOutOnRedeem;

    constructor(
        uint64 poolId_,
        bytes16 trancheId_,
        uint128 currencyId_,
        address _liquidityPool,
        address mockCentrifugeChain_,
        address erc20_,
        address escrow_
    ) {
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
    function requestDeposit(uint128 amount) public {
        // Don't allow total outstanding deposit requests > type(uint128).max
        amount =
            uint128(bound(amount, 0, uint128(type(uint128).max - totalDepositRequested + totalCurrencyPaidOutOnInvest)));

        erc20.mint(address(this), amount);
        erc20.approve(investmentManager, amount);
        liquidityPool.requestDeposit(uint256(amount), address(this));

        totalDepositRequested += uint256(amount);
    }

    function deposit(uint128 amount) public {
        uint256 amount_ = bound(amount, 0, liquidityPool.maxDeposit(address(this)));

        liquidityPool.deposit(amount_, address(this));
    }

    function mint(uint128 amount) public {
        uint256 amount_ = bound(amount, 0, liquidityPool.maxMint(address(this)));

        liquidityPool.mint(amount_, address(this));
    }

    // --- Redemptions ---
    function requestRedeem(uint128 amount) public {
        amount = uint128(
            bound(
                amount,
                0,
                _min(
                    // Don't allow total outstanding redeem requests > type(uint128).max
                    uint128(type(uint128).max - totalRedeemRequested + totalTrancheTokensPaidOutOnRedeem),
                    // Cannot redeem more than current balance of TT
                    trancheToken.balanceOf(address(this))
                )
            )
        );

        liquidityPool.requestRedeem(uint256(amount), address(this));

        totalRedeemRequested += uint256(amount);
    }

    function redeem(uint128 amount) public {
        uint256 amount_ = bound(amount, 0, liquidityPool.maxRedeem(address(this)));

        uint256 preBalance = erc20.balanceOf(address(this));
        liquidityPool.redeem(amount_, address(this), address(this));
        uint256 postBalance = erc20.balanceOf(address(this));
        totalCurrencyReceived += postBalance - preBalance;
    }

    function withdraw(uint128 amount) public {
        uint256 amount_ = bound(amount, 0, liquidityPool.maxWithdraw(address(this)));

        uint256 preBalance = erc20.balanceOf(address(this));
        liquidityPool.withdraw(amount_, address(this), address(this));
        uint256 postBalance = erc20.balanceOf(address(this));
        totalCurrencyReceived += postBalance - preBalance;
    }

    // --- Misc ---
    /// @dev Simulate deposit from another user into the escrow
    function randomDeposit(uint128 amount) public {
        trancheToken.mint(escrow, amount);
    }

    // TODO: should be moved to a separate contract
    function executedCollectInvest(uint256 fulfillmentRatio, uint256 fulfillmentPrice) public {
        fulfillmentRatio = bound(fulfillmentRatio, 0, 1 * 10 ** 18); // 0% to 100%
        fulfillmentPrice = bound(fulfillmentPrice, 0, 2 * 10 ** 18); // 0.00 to 2.00

        uint256 outstandingDepositRequest = totalDepositRequested - totalCurrencyPaidOutOnInvest;

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
            bytes32(bytes20(address(this))),
            currencyId,
            currencyPayout,
            trancheTokenPayout,
            uint128(outstandingDepositRequest - currencyPayout)
        );

        totalCurrencyPaidOutOnInvest += currencyPayout;
        totalTrancheTokensPaidOutOnInvest += trancheTokenPayout;
    }

    function executedCollectRedeem(uint256 fulfillmentRatio, uint256 fulfillmentPrice) public {
        fulfillmentRatio = bound(fulfillmentRatio, 0, 1 * 10 ** 18); // 0% to 100%
        fulfillmentPrice = bound(fulfillmentPrice, 0, 2 * 10 ** 18); // 0.00 to 2.00

        uint256 outstandingRedeemRequest = totalRedeemRequested - totalTrancheTokensPaidOutOnRedeem;

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
            bytes32(bytes20(address(this))),
            currencyId,
            currencyPayout,
            trancheTokenPayout,
            uint128(outstandingRedeemRequest - currencyPayout)
        );

        totalTrancheTokensPaidOutOnRedeem += trancheTokenPayout;
        totalCurrencyPaidOutOnRedeem += currencyPayout;
    }

    /// @notice Returns the smallest of two numbers.
    function _min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a > b ? b : a;
    }
}
