// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.26;

import {Auth} from "src/Auth.sol";
import {IERC20} from "src/interfaces/IERC20.sol";
import {IERC7540Vault} from "src/interfaces/IERC7540.sol";
import {IPoolManager} from "src/interfaces/IPoolManager.sol";
import {MathLib} from "src/libraries/MathLib.sol";
import {IInterestDistributor} from "src/interfaces/operators/IInterestDistributor.sol";

/// @title  InterestDistributor
/// @notice
contract InterestDistributor is Auth, IInterestDistributor {
    using MathLib for uint256;

    struct UserDetails {
        uint256 latestPrice;
        uint64 lastPriceUpdate;
        uint128 outstandingShares;
    }

    mapping(address vault => mapping(address user => UserDetails)) internal _users;

    constructor() Auth(msg.sender) {}

    /// @inheritdoc IInterestDistributor
    function distribute(address vault_, address user_) public {
        IERC7540Vault vault = IERC7540Vault(vault_);
        require(vault.isOperator(user_, address(this)), "InterestDistributor/not-an-operator");

        UserDetails storage user = _users[vault_][user_];
        uint64 priceLastUpdated = vault.priceLastUpdated();

        if (user.lastPriceUpdate == priceLastUpdated) {
            // No price update since last distribute() call
            return;
        }

        // Calculate before updating user.shares, so it's based on the balance of the last price update.
        // Assuming price updates coincide with epoch fulfillments, this has the effect of only requesting
        // interest on the previous balance before the new fulfillment.
        uint256 newPrice = vault.pricePerShare();
        uint128 request = _calculateSharesToRedeem(user.outstandingShares, user.latestPrice, newPrice);

        user.latestPrice = newPrice;
        user.lastPriceUpdate = priceLastUpdated;
        user.outstandingShares = IERC20(vault.share()).balanceOf(user_).toUint128();

        if (request > 0) vault.requestRedeem(request, user_, user_);
        emit Distribute(vault_, user_, request);
    }

    /// @inheritdoc IInterestDistributor
    function clear(address vault_, address user_) external {
        IERC7540Vault vault = IERC7540Vault(vault_);
        require(!vault.isOperator(user_, address(this)), "InterestDistributor/still-an-operator");

        UserDetails storage user = _users[vault_][user_];
        require(user.outstandingShares > 0, "InterestDistributor/no-outstanding-shares");

        user.latestPrice = 0;
        user.lastPriceUpdate = 0;
        user.outstandingShares = 0;
        emit Clear(vault_, user_);
    }

    /// @inheritdoc IInterestDistributor
    function pending(address vault_, address user_) external view returns (uint128) {
        UserDetails memory user = _users[vault_][user_];
        if (user.lastPriceUpdate == IERC7540Vault(vault_).priceLastUpdated()) return 0;
        return _calculateSharesToRedeem(user.outstandingShares, user.latestPrice, IERC7540Vault(vault_).pricePerShare());
    }

    /// @dev Calculate shares to redeem based on outstandingShares * ((newPrice - prevPrice) / prevPrice)
    function _calculateSharesToRedeem(uint128 outstandingShares, uint256 prevPrice, uint256 newPrice)
        internal
        view
        returns (uint128 shares)
    {
        if (outstandingShares == 0 || newPrice <= prevPrice) {
            return 0;
        }

        shares = uint256(outstandingShares).mulDiv(newPrice - prevPrice, prevPrice, MathLib.Rounding.Down).toUint128();
    }
}
