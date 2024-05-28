// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.5.0;

interface ICentrifugeRouter {
    // --- Events ---
    event LockDepositRequest(address indexed vault, address indexed user, uint256 amount);
    event UnlockDepositRequest(address indexed vault, address indexed user);
    event ExecuteLockedDepositRequest(address indexed vault, address indexed user);

    /// @notice TODO
    function lockedRequests(address user, address vault) external view returns (uint256 amount);

    // --- Administration ---
    /// @notice TODO
    function recoverTokens(address token, address to, uint256 amount) external;

    // --- Deposit ---
    /// @notice TODO
    function requestDeposit(address vault, uint256 amount) external;

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
}