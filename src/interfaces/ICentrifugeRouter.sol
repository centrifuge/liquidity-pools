// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.5.0;

import {IMulticall} from "src/interfaces/IMulticall.sol";

interface ICentrifugeRouter is IMulticall {
    // --- Events ---
    event LockDepositRequest(address indexed vault, address indexed user, uint256 amount);
    event UnlockDepositRequest(address indexed vault, address indexed user);
    event ExecuteLockedDepositRequest(address indexed vault, address indexed user);
    event File(bytes32 indexed what, address data);

    /// @notice TODO
    function lockedRequests(address controller, address vault) external view returns (uint256 amount);

    // --- Administration ---
    /// @notice TODO
    function file(bytes32 what, address data) external;

    /// @notice TODO
    function recoverTokens(address token, address to, uint256 amount) external;

    // --- Deposit ---
    /// @notice TODO
    function requestDeposit(address vault, uint256 amount, address controller, address owner) external;

    /// @notice TODO
    function lockDepositRequest(address vault, uint256 amount, address controller, address owner) external;

    /// @notice TODO
    function unlockDepositRequest(address vault) external;

    /// @notice TODO
    function executeLockedDepositRequest(address vault, address controller) external;

    /// @notice TODO
    function claimDeposit(address vault, address receiver, address controller) external;

    // --- Redeem ---
    /// @notice TODO
    function requestRedeem(address vault, uint256 amount, address controller, address owner) external;

    /// @notice TODO
    function claimRedeem(address vault, address receiver, address controller) external;

    // --- ERC20 permit ---
    /// @notice TODO
    function permit(address asset, address spender, uint256 assets, uint256 deadline, uint8 v, bytes32 r, bytes32 s)
        external;

    // --- ERC20 wrapping ---
    /// @notice TODO
    function wrap(address wrapper, uint256 amount, address receiver) external;

    /// @notice TODO
    function unwrap(address wrapper, uint256 amount, address receiver) external;

    // --- View Methods ---
    /// @notice TODO
    function getVault(uint64 poolId, bytes16 trancheId, address asset) external view returns (address);
}
