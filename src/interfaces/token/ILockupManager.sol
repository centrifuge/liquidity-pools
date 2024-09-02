// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.5.0;

import {HookData} from "src/interfaces/token/IHook.sol";

enum RestrictionUpdate {
    Invalid,
    UpdateMember,
    Freeze,
    Unfreeze,
    SetLockupPeriod,
    ForceUnlock
}

struct LockupConfig {
    uint64 referenceDate; // UTC midnight reference
    uint32 time; // seconds since UTC midnight
    uint16 lockupDays; // type(uint16).max / 365 = 179 years
    bool locksTransfers;
}

struct Transfer {
    uint128 amount; // TODO: change to aggregate unlocked?
    uint16 next; // days since referenceDate
}

struct LockupData {
    uint16 first; // days since referenceDate
    uint16 last; // days since referenceDate
    uint128 unlocked; // already deducted from transfers mapping
    uint128 transferred; // not yet deducted from transfers mapping
    mapping(uint16 => Transfer) transfers;
}

interface ILockupManager {
    // --- Events ---
    event Lock(address indexed token, address indexed user, uint256 amount, uint64 lockedUntil);
    event SetLockupPeriod(address indexed token, uint16 lockupDays, uint32 time);
    event ForceUnlock(address indexed token, address indexed user);
    event UpdateMember(address indexed token, address indexed user, uint64 validUntil);
    event Freeze(address indexed token, address indexed user);
    event Unfreeze(address indexed token, address indexed user);

    /// @notice Check if given transfer can be performed
    function checkERC20Transfer(
        address from,
        address to,
        uint256 value,
        HookData calldata hookData,
        uint128 unlockedBalance
    ) external view returns (bool);

    // --- Lockup period ---
    /// @notice TODO
    ///
    /// @dev    referenceDate: Aug 1st
    ///         block.timestamp: Aug 15th
    ///
    ///         Lockups are stored as days since referenceDate. So it should be 15 days.
    ///
    ///         daysSinceReferenceDate = (block.timestamp / (1 days)) - (referenceDate / (1 days))
    function setLockupPeriod(address token, uint16 lockupDays, uint32 time) external;

    /// @notice TODO
    function forceUnlock(address token, address user) external;

    /// @notice TODO
    function unlocked(address token, address user) external view returns (uint128);

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
