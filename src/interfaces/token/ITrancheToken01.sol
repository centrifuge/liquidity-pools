// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import {IERC20} from "src/interfaces/IERC20.sol";

interface ITrancheToken01 {
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
    event File(bytes32 indexed what, address data);
    event File(bytes32 indexed what, address data1, address data2);

    // --- Administration ---
    /// @notice TODO
    function file(bytes32 what, address data1, address data2) external;

    // --- Incoming message handling ---
    /// @notice TODO
    function updateRestriction(bytes memory update) external;

    // --- ERC1404 implementation ---
    /// @notice TODO
    function checkTransferRestriction(address from, address to, uint256 value) external view returns (bool);

    /// @notice TODO
    function detectTransferRestriction(address from, address to, uint256 /* value */ ) external view returns (uint8);

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
