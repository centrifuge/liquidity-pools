// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.5.0;

interface IRestrictionManager {
    struct Restrictions {
        /// @dev Frozen accounts that tokens cannot be transferred from or to
        bool frozen;
        /// @dev Member accounts that tokens can be transferred to, with an end date
        uint64 validUntil;
    }

    // --- Events ---
    event UpdateMember(address indexed user, uint64 validUntil);
    event Freeze(address indexed user);
    event Unfreeze(address indexed user);

    // --- ERC1404 implementation ---
    /// @notice TODO
    // function detectTransferRestriction(address from, address to, uint256 /* value */ ) external view returns (uint8);

    /// @notice TODO
    function messageForTransferRestriction(uint8 restrictionCode) external pure returns (string memory);

    // --- Handling freezes ---
    /// @notice TODO
    function freeze(address user) external;

    /// @notice TODO
    function unfreeze(address user) external;

    // --- Managing members ---
    /// @notice TODO
    function updateMember(address user, uint64 validUntil) external;
}
