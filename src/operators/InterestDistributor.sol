// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.26;

import {IERC20} from "src/interfaces/IERC20.sol";
import {IERC7540Vault} from "src/interfaces/IERC7540.sol";
import {IPoolManager} from "src/interfaces/IPoolManager.sol";
import {MathLib} from "src/libraries/MathLib.sol";
import {IInterestDistributor, InterestDetails} from "src/interfaces/operators/IInterestDistributor.sol";

/// @title  InterestDistributor
/// @notice Contract that can be enabled by calling vault.setOperator(address(interestDistributor), true), which then
///         allows permissionless triggers of redeem requests for the accrued interest on a vault.
///
///         Whenever a user claims new tranche tokens or a principal redeem request is initiated,
///         distribute() should be called to update the outstanding shares that the interest is computed based on.
///
///         Uses peak price to calculate interest. If the price goes down, interest will only be redeemed
///         again once the price fully recovers above the previous high point (peak).
///         Peak is stored per user since if the price has globally gone down, and a user invests at that time,
///         they'd expect to redeem interest based on the price they invested in, not the previous high point.
/// @dev    Requires that:
///         - Whenever orders are fulfilled, an UpdateTranchePrice message is also submitted
///         - Users claim the complete fulfilled amount using the router, rather than partial claims through the vault.
///         Otherwise the interest amounts may be off.
contract InterestDistributor is IInterestDistributor {
    using MathLib for uint256;

    mapping(address vault => mapping(address user => InterestDetails)) internal _users;

    IPoolManager public immutable poolManager;

    constructor(address poolManager_) {
        poolManager = IPoolManager(poolManager_);
    }

    /// @inheritdoc IInterestDistributor
    function distribute(address vault, address controller) external {
        IERC7540Vault vault_ = IERC7540Vault(vault);
        require(vault_.isOperator(controller, address(this)), "InterestDistributor/not-an-operator");

        InterestDetails storage user = _users[vault][controller];
        uint128 prevShares = user.shares;

        (address asset,) = poolManager.getVaultAsset(vault);
        (uint128 currentPrice, uint64 priceLastUpdated) =
            poolManager.getTranchePrice(vault_.poolId(), vault_.trancheId(), asset);
        uint128 currentShares = IERC20(vault_.share()).balanceOf(controller).toUint128();

        // Calculate request before updating user.shares, so it is based on the balance at the last price update.
        // Assuming price updates coincide with epoch fulfillments, this results in only requesting
        // interest on the previous outstanding balance before the new fulfillment.
        uint128 request = priceLastUpdated > user.lastUpdate
            ? _computeRequest(user.shares, currentShares, user.peak, uint96(currentPrice))
            : 0;

        user.lastUpdate = uint32(priceLastUpdated);
        if (currentPrice > user.peak) user.peak = uint96(currentPrice);
        user.shares = currentShares - request;

        if (request > 0) {
            vault_.requestRedeem(request, controller, controller);
            emit InterestRedeemRequest(vault, controller, user.peak, uint96(currentPrice), request);
        }

        if (user.shares != prevShares) {
            emit OutstandingSharesUpdate(vault, controller, prevShares, user.shares);
        }
    }

    /// @inheritdoc IInterestDistributor
    function clear(address vault, address controller) external {
        require(!IERC7540Vault(vault).isOperator(controller, address(this)), "InterestDistributor/still-an-operator");
        require(_users[vault][controller].lastUpdate > 0, "InterestDistributor/unknown-controller");

        delete _users[vault][controller];
        emit Clear(vault, controller);
    }

    /// @inheritdoc IInterestDistributor
    function pending(address vault, address controller) external view returns (uint128 shares) {
        InterestDetails memory user = _users[vault][controller];
        IERC7540Vault vault_ = IERC7540Vault(vault);
        (uint128 currentPrice, uint64 priceLastUpdated) =
            poolManager.getTranchePrice(vault_.poolId(), vault_.trancheId(), vault_.asset());
        if (user.lastUpdate == uint32(priceLastUpdated)) return 0;
        shares =
            _computeRequest(user.shares, IERC20(vault_.share()).balanceOf(controller), user.peak, uint96(currentPrice));
    }

    /// @dev Calculate shares to redeem based on outstandingShares * ((currentPrice - prevPrice) / currentPrice)
    function _computeRequest(uint128 outstandingShares, uint256 currentShares, uint96 prevPrice, uint96 currentPrice)
        internal
        pure
        returns (uint128)
    {
        if (outstandingShares == 0 || currentPrice <= prevPrice) return 0;

        // If there was a principal redemption, the current balance is used since more than that cannot be redeemed.
        return MathLib.min(
            uint256(outstandingShares).mulDiv(currentPrice - prevPrice, currentPrice, MathLib.Rounding.Down),
            currentShares
        ).toUint128();
    }
}
