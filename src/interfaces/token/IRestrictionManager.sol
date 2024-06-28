// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.5.0;

interface IRestrictionManager {
    // --- Events ---
    event UpdateMember(address indexed token, address indexed user, uint64 validUntil);
    event Freeze(address indexed token, address indexed user);
    event Unfreeze(address indexed token, address indexed user);

    // --- ERC1404 implementation ---
    /// @notice TODO
    // function detectTransferRestriction(address from, address to, uint256 /* value */ ) external view returns (uint8);

    /// @notice TODO
    function messageForTransferRestriction(uint8 restrictionCode) external pure returns (string memory);

    function updateRestriction(address token, bytes memory update) external;
    function isFrozen(address token, address user) external view returns (bool);
    function isMember(address token, address user) external view returns (bool);

    // --- Handling freezes ---
    /// @notice TODO
    function freeze(address token, address user) external;

    /// @notice TODO
    function unfreeze(address token, address user) external;

    // --- Managing members ---
    /// @notice TODO
    function updateMember(address token, address user, uint64 validUntil) external;
}
