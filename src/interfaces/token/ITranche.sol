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
    /// @notice returns the hook that transfers perform callbacks to
    /// @dev    MUST comply to `IHook` interface
    function hook() external view returns (address);

    /// @notice Updates a contract parameter
    /// @param what Accepts a bytes32 representation of 'name', 'symbol'
    function file(bytes32 what, string memory data) external;

    /// @notice Updates a contract parameter
    /// @param what Accepts a bytes32 representation of 'hook'
    function file(bytes32 what, address data) external;

    /// @notice updates the vault for a given `asset`
    function updateVault(address asset, address vault_) external;

    // --- ERC20 overrides ---
    /// @notice returns the 16 byte hook data of the given `user`.
    /// @dev    Stored in the 128 most significant bits of the user balance
    function hookDataOf(address user) external view returns (bytes16);

    /// @notice update the 16 byte hook data of the given `user`
    function setHookData(address user, bytes16 hookData) external;

    /// @notice Function to mint tokens
    function mint(address user, uint256 value) external;

    /// @notice Function to burn tokens
    function burn(address user, uint256 value) external;

    /// @notice Checks if the tokens can be transferred given the input values
    function checkTransferRestriction(address from, address to, uint256 value) external view returns (bool);

    /// @notice Performs an authorized transfer, with `sender` as the given sender.
    /// @dev    Requires allowance if `sender` != `from`
    function authTransferFrom(address sender, address from, address to, uint256 amount) external returns (bool);
}
