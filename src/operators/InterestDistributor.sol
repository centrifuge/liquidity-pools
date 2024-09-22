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
contract InterestDistributor is IInterestDistributor {
    using MathLib for uint256;

    mapping(address vault => mapping(address user => InterestDetails)) internal _users;

    /// @inheritdoc IInterestDistributor
    function distribute(address vault, address controller) external {
        IERC7540Vault vault_ = IERC7540Vault(vault);
        require(vault_.isOperator(controller, address(this)), "InterestDistributor/not-an-operator");

        InterestDetails storage user = _users[vault][controller];
        uint32 priceLastUpdated = uint32(vault_.priceLastUpdated());
        if (user.lastUpdate == priceLastUpdated) return;

        uint128 prevOutstandingShares = user.shares;
        uint96 currentPrice = uint96(vault_.pricePerShare());

        // Calculate before updating user.shares, so it's based on the balance of the last price update.
        // Assuming price updates coincide with epoch fulfillments, this results in only requesting
        // interest on the previous outstanding balance before the new fulfillment.
        uint128 request = _computeRequest(user.shares, user.peak, currentPrice);

        user.lastUpdate = priceLastUpdated;
        if (currentPrice > user.peak) user.peak = uint96(currentPrice);
        user.shares = IERC20(vault_.share()).balanceOf(controller).toUint128() - request;

        if (request > 0) {
            vault_.requestRedeem(request, controller, controller);
            emit InterestRedeemRequest(vault, controller, user.peak, currentPrice, request);
        }

        if (user.shares != prevOutstandingShares) {
            emit OutstandingSharesUpdate(vault, controller, prevOutstandingShares, user.shares);
        }
    }

    /// @inheritdoc IInterestDistributor
    function clear(address vault, address controller) external {
        require(!IERC7540Vault(vault).isOperator(controller, address(this)), "InterestDistributor/still-an-operator");
        require(_users[vault][controller].shares > 0, "InterestDistributor/no-outstanding-shares");

        delete _users[vault][controller];
        emit Clear(vault, controller);
    }

    /// @inheritdoc IInterestDistributor
    function pending(address vault, address controller) external view returns (uint128 shares) {
        InterestDetails memory user = _users[vault][controller];
        if (user.lastUpdate == IERC7540Vault(vault).priceLastUpdated()) return 0;
        shares = _computeRequest(user.shares, user.peak, uint96(IERC7540Vault(vault).pricePerShare()));
    }

    /// @dev Calculate shares to redeem based on shares * ((currentPrice - prevPrice) / currentPrice)
    function _computeRequest(uint128 shares, uint96 prevPrice, uint96 currentPrice) internal pure returns (uint128) {
        if (shares == 0 || currentPrice <= prevPrice) return 0;
        return uint256(shares).mulDiv(currentPrice - prevPrice, currentPrice, MathLib.Rounding.Down).toUint128();
    }
}
