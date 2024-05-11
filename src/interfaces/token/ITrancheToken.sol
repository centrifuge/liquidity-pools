// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.5.0;

interface ITrancheToken {
    // --- Events ---
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
}
