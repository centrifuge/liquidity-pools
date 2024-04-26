// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

interface IRoot {
    // --- Events ---
    event File(bytes32 indexed what, uint256 data);
    event Pause();
    event Unpause();
    event ScheduleRely(address indexed target, uint256 indexed scheduledTime);
    event CancelRely(address indexed target);
    event RelyContract(address indexed target, address indexed user);
    event DenyContract(address indexed target, address indexed user);
    event RecoverTokens(address indexed target, address indexed token, address indexed to, uint256 amount);

    // --- Administration ---
    /// @notice TODO
    function file(bytes32 what, uint256 data) external;

    // --- Pause management ---
    /// @notice Pause any contracts that depend on `Root.paused()`
    function pause() external;

    /// @notice Unpause any contracts that depend on `Root.paused()`
    function unpause() external;

    /// --- Timelocked ward management ---
    /// @notice Schedule relying a new ward after the delay has passed
    function scheduleRely(address target) external;

    /// @notice Cancel a pending scheduled rely
    function cancelRely(address target) external;

    /// @notice Execute a scheduled rely
    /// @dev    Can be triggered by anyone since the scheduling is protected
    function executeScheduledRely(address target) external;

    /// --- Incoming message handling ---
    function handle(bytes calldata message) external;

    /// --- External contract ward management ---
    /// @notice Make an address a ward on any contract that Root is a ward on
    function relyContract(address target, address user) external;

    /// @notice Removes an address as a ward on any contract that Root is a ward on
    function denyContract(address target, address user) external;

    /// --- Token Recovery ---
    /// @notice Allows Governance to recover tokens sent to the wrong contract by mistake
    function recoverTokens(address target, address token, address to, uint256 amount) external;
}
