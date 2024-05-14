// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.5.0;

import {IERC20} from "src/interfaces/IERC20.sol";

interface ITrancheToken {
    // --- Events ---
    event File(bytes32 indexed what, address data);
    event File(bytes32 indexed what, address data1, address data2);

    // --- Administration ---
    /// @notice TODO
    function file(bytes32 what, address data) external;

    /// @notice TODO
    function file(bytes32 what, address data1, address data2) external;

    // --- ERC1404 implementation ---
    /// @notice TODO
    function detectTransferRestriction(address from, address to, uint256 value) external view returns (uint8);

    /// @notice TODO
    function checkTransferRestriction(address from, address to, uint256 value) external view returns (bool);

    /// @notice TODO
    function messageForTransferRestriction(uint8 restrictionCode) external view returns (string memory);

    /// @notice TODO
    function SUCCESS_CODE() external view returns (uint8);
}
