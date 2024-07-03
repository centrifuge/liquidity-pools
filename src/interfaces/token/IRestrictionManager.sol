// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.5.0;

enum RestrictionUpdate {
    Invalid,
    UpdateMember,
    Freeze,
    Unfreeze
}

interface IRestrictionManager {
    // --- Events ---
    event UpdateMember(address indexed token, address indexed user, uint64 validUntil);
    event Freeze(address indexed token, address indexed user);
    event Unfreeze(address indexed token, address indexed user);

    // --- Handling freezes ---
    /// @notice TODO
    function freeze(address token, address user) external;

    /// @notice TODO
    function unfreeze(address token, address user) external;

    /// @notice TODO
    function isFrozen(address token, address user) external view returns (bool);

    // --- Managing members ---
    /// @notice TODO
    function updateMember(address token, address user, uint64 validUntil) external;

    /// @notice TODO
    function isMember(address token, address user) external view returns (bool);
}
