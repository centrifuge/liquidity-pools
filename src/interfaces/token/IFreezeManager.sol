// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.5.0;

enum RestrictionUpdate {
    Invalid,
    Invalid,
    Freeze,
    Unfreeze
}

interface IFreezeManager {
    // --- Events ---
    event Freeze(address indexed token, address indexed user);
    event Unfreeze(address indexed token, address indexed user);

    // --- Handling freezes ---
    /// @notice Freeze a user balance. Frozen users cannot receive nor send tokens
    function freeze(address token, address user) external;

    /// @notice Unfreeze a user balance
    function unfreeze(address token, address user) external;

    /// @notice Returns whether the user's tokens are frozen
    function isFrozen(address token, address user) external view returns (bool);
}
