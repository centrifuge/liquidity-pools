// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.26;

import {Auth} from "src/Auth.sol";
import {IERC20} from "src/interfaces/IERC20.sol";
import {IERC7540Vault} from "src/interfaces/IERC7540.sol";
import {IPoolManager} from "src/interfaces/IPoolManager.sol";
import {MathLib} from "src/libraries/MathLib.sol";
import {IInterestDistributor, InterestDetails} from "src/interfaces/operators/IInterestDistributor.sol";

/// @title  InterestDistributor
/// @notice Contract that can be set as an operator of a controller for a vault, which then enables
///         permissionless triggers of redeem requests for the accrued interest on a vault.
///
///         Whenever a user claims new tranche tokens or a principal redeem request is initiated,
///         distribute() should be called to update the outstanding shares that the interest is computed based on.
contract InterestDistributor is Auth, IInterestDistributor {
    using MathLib for uint256;

    mapping(address vault => mapping(address user => InterestDetails)) internal _users;

    constructor() Auth(msg.sender) {}

    /// @inheritdoc IInterestDistributor
    function distribute(address vault_, address user_) external {
        IERC7540Vault vault = IERC7540Vault(vault_);
        require(vault.isOperator(user_, address(this)), "InterestDistributor/not-an-operator");

        InterestDetails storage user = _users[vault_][user_];
        uint64 priceLastUpdated = vault.priceLastUpdated();

        if (user.lastDistribution == priceLastUpdated) {
            return;
        }

        // Use peak price to calculate interest. If the price goes down, interest will only be redeemed
        // again once the price fully recovers above the previous high point (peak).
        // Peak is stored per user since if the price has globally gone down, and a user invests at that time,
        // they'd expect to redeem interest based on the price they invested in, not the previous high point.
        uint256 currentPrice = vault.pricePerShare();
        if (currentPrice < user.peak) return;
        uint256 comparison = uint256(user.latestPrice) < user.peak ? user.peak : uint256(user.latestPrice);

        // Calculate before updating user.shares, so it's based on the balance of the last price update.
        // Assuming price updates coincide with epoch fulfillments, this has the effect of only requesting
        // interest on the previous balance before the new fulfillment.
        uint128 request = _computeRequest(user.outstandingShares, comparison, currentPrice);

        uint128 prevOutstandingShares = user.outstandingShares;
        user.latestPrice = uint32(currentPrice);
        if (currentPrice > user.peak) user.peak = uint32(currentPrice);
        user.lastDistribution = priceLastUpdated;
        user.outstandingShares = IERC20(vault.share()).balanceOf(user_).toUint128();

        if (request > 0) {
            vault.requestRedeem(request, user_, user_);
            emit InterestRedeemRequest(vault_, user_, comparison, currentPrice, request);
        }

        if (user.outstandingShares != prevOutstandingShares) {
            emit OutstandingSharesUpdate(vault_, user_, prevOutstandingShares, user.outstandingShares);
        }
    }

    /// @inheritdoc IInterestDistributor
    function clear(address vault_, address user_) external {
        require(!IERC7540Vault(vault_).isOperator(user_, address(this)), "InterestDistributor/still-an-operator");
        require(_users[vault_][user_].outstandingShares > 0, "InterestDistributor/no-outstanding-shares");

        delete _users[vault_][user_];
        emit Clear(vault_, user_);
    }

    /// @inheritdoc IInterestDistributor
    function pending(address vault_, address user_) external view returns (uint128 shares) {
        InterestDetails memory user = _users[vault_][user_];
        if (user.lastDistribution == IERC7540Vault(vault_).priceLastUpdated()) return 0;
        uint256 currentPrice = IERC7540Vault(vault_).pricePerShare();
        if (currentPrice < user.peak) return 0;
        uint256 comparison = uint256(user.latestPrice) < user.peak ? user.peak : uint256(user.latestPrice);
        shares = _computeRequest(user.outstandingShares, comparison, currentPrice);
    }

    /// @dev Calculate shares to redeem based on outstandingShares * ((currentPrice - prevPrice) / currentPrice)
    function _computeRequest(uint128 outstandingShares, uint256 prevPrice, uint256 currentPrice)
        internal
        pure
        returns (uint128 shares)
    {
        if (outstandingShares == 0 || currentPrice <= prevPrice) {
            return 0;
        }

        shares =
            uint256(outstandingShares).mulDiv(currentPrice - prevPrice, currentPrice, MathLib.Rounding.Down).toUint128();
    }
}
