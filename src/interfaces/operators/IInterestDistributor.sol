// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.5.0;

enum RestrictionUpdate {
    Invalid,
    UpdateMember,
    Freeze,
    Unfreeze
}

interface IInterestDistributor {
    // --- Events ---
    event Distribute(address indexed vault, address indexed user, uint128 request);
    event Clear(address indexed vault, address indexed user);

    /// @notice Trigger redeem request of pending interest for a user who has set the interest distributor
    ///         as an operator for the given vault.
    ///         Should be called after any fulfillment to update the outstanding shares. Interest is only redeemed
    ///         in the next price update after the first distribute() call post fulfillment.
    function distribute(address vault_, address user_) external;

    /// @notice Called by users to disable the use of the interest distributor, after they have called
    ///         setOperator(address(interestDistributor), false)
    function clear(address vault_, address user_) external;

    /// @notice Returns the pending interest to be redeemed.
    function pending(address vault_, address user_) external view returns (uint128);
}
