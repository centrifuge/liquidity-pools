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
    function updateVault(address asset, address vault_) external;

    /// @notice TODO
    function checkTransferRestriction(address from, address to, uint256 value) external view returns (bool);
}
