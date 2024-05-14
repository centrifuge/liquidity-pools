// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.5.0;

import {ITrancheToken} from "src/interfaces/token/ITrancheToken.sol";

interface ITrancheToken01 is ITrancheToken {
    struct Restrictions {
        /// @dev Member accounts that tokens can be transferred to, with an end date
        uint64 validUntil;
    }

    // --- Events ---
    event UpdateMember(address indexed user, uint64 validUntil);
    event Freeze(address indexed user);
    event Unfreeze(address indexed user);

    // --- ERC1404 implementation ---
    /// @notice TODO
    function detectTransferRestriction(address from, address to, uint256 /* value */ ) external view returns (uint8);

    /// @notice TODO
    function messageForTransferRestriction(uint8 restrictionCode) external pure returns (string memory);

    // --- Handling freezes ---
    /// @notice TODO
    function freeze(address user) external;

    /// @notice TODO
    function unfreeze(address user) external;

    /// @notice TODO
    function isFrozen(address user) external view returns (bool);

    // --- Managing members ---
    /// @notice TODO
    function updateMember(address user, uint64 validUntil) external;

    /// @dev Permissionless method that sets the membership bit to false once
    ///      the valid until date is in the past
    function setInvalidMember(address user) external;

    /// @notice TODO
    function isMember(address user) external view returns (bool);
}
