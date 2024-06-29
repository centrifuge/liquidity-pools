// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.5.0;

string constant SOURCE_IS_FROZEN_MESSAGE = "source-is-frozen";
string constant DESTINATION_IS_FROZEN_MESSAGE = "destination-is-frozen";
string constant DESTINATION_NOT_A_MEMBER_RESTRICTION_MESSAGE = "destination-not-a-member";

uint8 constant FREEZE_BIT = 127;
uint8 constant MEMBER_BIT = 126;

uint8 constant SOURCE_IS_FROZEN_CODE = 1;
uint8 constant DESTINATION_IS_FROZEN_CODE = 2;
uint8 constant DESTINATION_NOT_A_MEMBER_RESTRICTION_CODE = 3;

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
