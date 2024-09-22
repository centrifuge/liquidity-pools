// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.5.0;

struct InterestDetails {
    /// @dev Time of the last price update after which a distribution happened.
    ///      Downcast from uint64 so only works until 2106.
    uint32 lastUpdate;
    /// @dev Highest recorded price (downcast from uint256)
    uint96 peak;
    /// @dev Outstanding shares on which the interest calculation is based.
    uint128 shares;
}

interface IInterestDistributor {
    // --- Events ---
    event InterestRedeemRequest(
        address indexed vault, address indexed controller, uint256 previousPrice, uint256 currentPrice, uint128 request
    );
    event OutstandingSharesUpdate(address indexed vault, address indexed controller, uint128 previous, uint128 current);
    event Clear(address indexed vault, address indexed controller);

    /// @notice Trigger redeem request of pending interest for a controller who has set the interest distributor
    ///         as an operator for the given vault.
    ///         Should be called after any fulfillment to update the outstanding shares.
    ///         Interest is only redeemed in the next price update after the first distribute() call post fulfillment.
    function distribute(address vault, address controller) external;

    /// @notice Called by controllers to disable the use of the interest distributor, after they have called
    ///         setOperator(address(interestDistributor), false)
    function clear(address vault, address controller) external;

    /// @notice Returns the pending interest to be redeemed.
    function pending(address vault, address controller) external view returns (uint128 shares);
}
