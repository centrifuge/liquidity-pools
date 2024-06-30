// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.5.0;

import {IERC20Metadata} from "src/interfaces/IERC20.sol";
import {IERC7575Share} from "src/interfaces/IERC7575.sol";

interface IERC1404 {
    function detectTransferRestriction(address from, address to, uint256 value) external view returns (uint8);
    function messageForTransferRestriction(uint8 restrictionCode) external view returns (string memory);
    function SUCCESS_CODE() external view returns (uint8);
}

// interface ITrancheToken is IERC20Metadata {
//     function mint(address user, uint256 value) external;
//     function burn(address user, uint256 value) external;
//     function file(bytes32 what, string memory data) external;
//     function file(bytes32 what, address data) external;
//     function updateVault(address asset, address vault) external;
//     function file(bytes32 what, address data1, bool data2) external;
//     function hook() external view returns (address);
//     function checkTransferRestriction(address from, address to, uint256 value) external view returns (bool);
//     function vault(address asset) external view returns (address);
// }

interface ITrancheToken is IERC20Metadata, IERC7575Share, IERC1404 {
    // --- Events ---
    event File(bytes32 indexed what, address data);
    event File(bytes32 indexed what, address data1, address data2);
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
