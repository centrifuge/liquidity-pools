// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.5.0;

import {IERC20Metadata} from "src/interfaces/IERC20.sol";
import {IERC7575Share} from "src/interfaces/IERC7575.sol";

interface IERC1404 {
    function detectTransferRestriction(address from, address to, uint256 value) external view returns (uint8);
    function messageForTransferRestriction(uint8 restrictionCode) external view returns (string memory);
    function SUCCESS_CODE() external view returns (uint8);
}

interface ITranche is IERC20Metadata, IERC7575Share, IERC1404 {
    // --- Events ---
    event File(bytes32 indexed what, address data);
    event SetHookData(address indexed user, bytes16 data);

    // --- Administration ---
    /// @notice TODO
    function hook() external view returns (address);

    /// @notice TODO
    function file(bytes32 what, string memory data) external;

    /// @notice TODO
    function file(bytes32 what, address data) external;

    /// @notice TODO
    function updateVault(address asset, address vault_) external;

    // --- ERC20 overrides ---
    /// @notice TODO
    function hookDataOf(address user) external view returns (bytes16);

    /// @notice TODO
    function setHookData(address user, bytes16 hookData) external;

    /// @notice TODO
    function mint(address user, uint256 value) external;

    /// @notice TODO
    function burn(address user, uint256 value) external;

    /// @notice TODO
    function checkTransferRestriction(address from, address to, uint256 value) external view returns (bool);

    /// @notice TODO
    function authTransferFrom(address sender, address from, address to, uint256 amount) external returns (bool);
}
