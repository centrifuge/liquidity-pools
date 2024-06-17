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
    function lockedRequests(address user, address vault) external view returns (uint256 amount);

    // --- Administration ---
    /// @notice TODO
    function recoverTokens(address token, address to, uint256 amount) external;

    /// @notice TODO
    function file(bytes32 what, address data) external;

    // --- Approval ---
    /// @notice TODO
    function approveVault(address vault) external;

    // --- Deposit ---
    /// @notice TODO
    function requestDeposit(address vault, uint256 amount, uint256 topUp) external payable;

    /// @notice TODO
    function lockDepositRequest(address vault, uint256 amount) external;

    /// @notice TODO
    function unlockDepositRequest(address vault) external;

    /// @notice TODO
    function executeLockedDepositRequest(address vault, address user) external;

    /// @notice TODO
    function claimDeposit(address vault, address user) external;

    // --- Redeem ---
    /// @notice TODO
    function requestRedeem(address vault, uint256 amount) external;

    /// @notice TODO
    function claimRedeem(address vault, address user) external;

    // --- View Methods ---
    /// @notice TODO
    function getVault(uint64 poolId, bytes16 trancheId, address asset) external view returns (address);
}
