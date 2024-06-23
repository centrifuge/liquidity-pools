// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.18;

import {MockCentrifugeChain} from "test/mocks/MockCentrifugeChain.sol";
import {MathLib} from "src/libraries/MathLib.sol";
import {IERC7540Vault} from "src/interfaces/IERC7540.sol";
import {BaseHandler} from "test/invariant/handlers/BaseHandler.sol";

interface ERC20Like {
    function mint(address user, uint256 amount) external;
    function approve(address spender, uint256 value) external returns (bool);
    function balanceOf(address user) external view returns (uint256);
}

interface VaultLike is IERC7540Vault {
    function share() external view returns (address);
    function manager() external view returns (address);
}

contract EpochExecutorHandler is BaseHandler {
    using MathLib for uint256;
    using MathLib for uint128;

    uint64 poolId;
    bytes16 trancheId;
    uint128 assetId;

    MockCentrifugeChain immutable centrifugeChain;

    constructor(uint64 poolId_, bytes16 trancheId_, uint128 assetId_, address mockCentrifugeChain_, address state_)
        BaseHandler(state_)
    {
        poolId = poolId_;
        trancheId = trancheId_;
        assetId = assetId_;

        centrifugeChain = MockCentrifugeChain(mockCentrifugeChain_);
    }

    function executedCollectInvest(uint256 investorSeed, uint256 fulfillmentRatio, uint256 fulfillmentPrice)
        public
        useRandomInvestor(investorSeed)
    {
        fulfillmentRatio = bound(fulfillmentRatio, 0, 1 * 10 ** 18); // 0% to 100%
        fulfillmentPrice = bound(fulfillmentPrice, 0, 2 * 10 ** 18); // 0.00 to 2.00

        uint256 outstandingDepositRequest =
            getVar(currentInvestor, "totalDepositRequested") - getVar(currentInvestor, "totalCurrencyPaidOutOnInvest");

        if (outstandingDepositRequest == 0) {
            return;
        }

        uint128 assets =
            uint128(outstandingDepositRequest.mulDiv(fulfillmentRatio, 1 * 10 ** 18, MathLib.Rounding.Down));
        uint128 shares = uint128(assets.mulDiv(1 * 10 ** 18, fulfillmentPrice, MathLib.Rounding.Down));

        centrifugeChain.isFulfilledDepositRequest(
            poolId,
            trancheId,
            bytes32(bytes20(currentInvestor)),
            assetId,
            assets,
            shares,
            uint128(outstandingDepositRequest - assets)
        );

        increaseVar(currentInvestor, "totalCurrencyPaidOutOnInvest", assets);
        increaseVar(currentInvestor, "totalTrancheTokensPaidOutOnInvest", shares);
        setMaxVar(currentInvestor, "maxDepositFulfillmentPrice", fulfillmentPrice);
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

        uint128 shares = uint128(outstandingRedeemRequest.mulDiv(fulfillmentRatio, 1 * 10 ** 18, MathLib.Rounding.Down));
        uint128 assets = uint128(shares.mulDiv(fulfillmentPrice, 1 * 10 ** 18, MathLib.Rounding.Down));

        centrifugeChain.isFulfilledRedeemRequest(
            poolId, trancheId, bytes32(bytes20(currentInvestor)), assetId, assets, shares
        );

        increaseVar(currentInvestor, "totalTrancheTokensPaidOutOnRedeem", shares);
        increaseVar(currentInvestor, "totalCurrencyPaidOutOnRedeem", assets);
        setMaxVar(currentInvestor, "maxRedeemFulfillmentPrice", fulfillmentPrice);
    }

    function executedDecreaseInvestOrder(uint256 investorSeed, uint256 decreaseRatio)
        public
        useRandomInvestor(investorSeed)
    {
        decreaseRatio = bound(decreaseRatio, 0, 1 * 10 ** 18); // 0% to 100%

        if (getVar(currentInvestor, "outstandingDecreaseDepositRequested") == 0) {
            return;
        }

        uint128 assets = uint128(
            getVar(currentInvestor, "outstandingDecreaseDepositRequested").mulDiv(
                decreaseRatio, 1 * 10 ** 18, MathLib.Rounding.Down
            )
        );

        centrifugeChain.isFulfilledCancelDepositRequest(
            poolId,
            trancheId,
            bytes32(bytes20(currentInvestor)),
            assetId,
            assets,
            uint128(getVar(currentInvestor, "outstandingDecreaseDepositRequested") - assets)
        );

        decreaseVar(currentInvestor, "outstandingDecreaseDepositRequested", assets);
        increaseVar(currentInvestor, "totalCurrencyPaidOutOnDecreaseInvest", assets);

        // An executed invest decrease indirectly leads to a redeem fulfillment at price 1.0
        setMaxVar(currentInvestor, "maxRedeemFulfillmentPrice", 1 * 10 ** 18);
    }
}
