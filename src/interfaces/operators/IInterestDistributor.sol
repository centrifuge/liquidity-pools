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

    /// @notice TODO
    function distribute(address vault_, address user_) external;
}
