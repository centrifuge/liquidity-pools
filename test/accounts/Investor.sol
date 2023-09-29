// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.18;
pragma abicoder v2;

import {TestSetup} from "test/TestSetup.t.sol";
import {MockCentrifugeChain} from "test/mock/MockCentrifugeChain.sol";
import {MathLib} from "src/util/MathLib.sol";
import {IERC4626} from "src/interfaces/IERC4626.sol";

import "forge-std/Test.sol";

interface ERC20Like {
    function mint(address user, uint256 amount) external;
    function approve(address spender, uint256 value) external returns (bool);
}

interface LiquidityPoolLike is IERC4626 {
    function requestDeposit(uint256 assets, address owner) external;
    function share() external view returns (address);
    function investmentManager() external view returns (address);
}

contract InvestorAccount is Test {
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
    uint256 public totalCurrencyPaidOut;
    uint256 public totalTrancheTokensPaidOut;

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
        investmentManager = liquidityPool.investmentManager();
    }

    // Simulate deposit from another user into the escrow
    function randomDeposit(uint128 amount) public {
        trancheToken.mint(escrow, amount);
    }

    function requestDeposit(uint128 amount) public {
        // Don't allow total outstanding deposit requests > type(uint128).max
        amount = uint128(bound(amount, 0, uint128(type(uint128).max - totalDepositRequested + totalCurrencyPaidOut)));

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

    // TODO: should be moved to a separate contract
    function executedCollectInvest(uint256 fulfillmentRatio, uint256 fulfillmentPrice) public {
        fulfillmentRatio = bound(fulfillmentRatio, 0, 1 * 10 ** 18); // 0% to 100%
        fulfillmentPrice = bound(fulfillmentPrice, 0, 2 * 10 ** 18); // 0.00 to 2.00

        uint256 outstandingDepositRequest = totalDepositRequested - totalCurrencyPaidOut;

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

        totalCurrencyPaidOut += currencyPayout;
        totalTrancheTokensPaidOut += trancheTokenPayout;
    }
}
