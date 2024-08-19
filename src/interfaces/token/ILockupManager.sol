// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.5.0;

enum RestrictionUpdate {
    Invalid,
    UpdateMember,
    Freeze,
    Unfreeze,
    SetLockupPeriod,
    ForceUnlock
}

interface ILockupManager {
    // --- Events ---
    event SetLockupPeriod(address indexed token, uint16 lockupDays);
    event AddLockup(address indexed token, address indexed user, uint64 lockedUntil, uint128 amount);
    event ForceUnlock(address indexed token, address indexed user);
    event UpdateMember(address indexed token, address indexed user, uint64 validUntil);
    event Freeze(address indexed token, address indexed user);
    event Unfreeze(address indexed token, address indexed user);

    // --- Lockup period ---
    /// @notice TODO
    ///
    /// @dev    referenceDate: Aug 1st
    ///         block.timestamp: Aug 15th
    ///         lockupDays: 7
    ///
    ///         When new tokens are minted, lockup should be until Aug 22nd.
    ///
    ///         Lockups are stored as days since referenceDate. So it should be 21 days.
    ///
    ///         daysSinceReferenceDate = (block.timestamp / (1 days)) - (referenceDate / (1 days)) + lockupDays
    function setLockupPeriod(address token, uint16 lockupDays) external;

    /// @notice TODO
    function isUnlocked(address token, address user, uint256 amount) external view returns (bool);

    /// @notice TODO
    function forceUnlock(address token, address user) external;

    // --- Handling freezes ---
    /// @notice Freeze a user balance. Frozen users cannot receive nor send tokens
    function freeze(address token, address user) external;

    /// @notice Unfreeze a user balance
    function unfreeze(address token, address user) external;

    /// @notice Returns whether the user's tokens are frozen
    function isFrozen(address token, address user) external view returns (bool);

    // --- Managing members ---
    /// @notice Add a member. Non-members cannot receive tokens, but can send tokens to valid members
    /// @param  validUntil Timestamp until which the user will be a valid member
    function updateMember(address token, address user, uint64 validUntil) external;

    /// @notice Returns whether the user is a valid member of the token
    function isMember(address token, address user) external view returns (bool isValid, uint64 validUntil);
}
