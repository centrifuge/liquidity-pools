// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.5.0;

import {IMessageHandler} from "src/interfaces/gateway/IGateway.sol";

interface IRecoverable {
    /// @notice Used to recover any ERC-20 token.
    /// @dev    This method is called only by authorized entities
    /// @param  token It could be 0xeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee
    ///         to recover locked native ETH or any ERC20 compatible token.
    /// @param  to Receiver of the funds
    /// @param  amount Amount to send to the receiver.
    function recoverTokens(address token, address to, uint256 amount) external;
}

interface IRoot is IMessageHandler {
    // --- Events ---
    event File(bytes32 indexed what, uint256 data);
    event Pause();
    event Unpause();
    event ScheduleRely(address indexed target, uint256 indexed scheduledTime);
    event CancelRely(address indexed target);
    event RelyContract(address indexed target, address indexed user);
    event DenyContract(address indexed target, address indexed user);
    event RecoverTokens(address indexed target, address indexed token, address indexed to, uint256 amount);
    event Endorse(address indexed user);
    event Veto(address indexed user);

    /// @notice Returns whether the root is paused
    function paused() external view returns (bool);

    /// @notice Returns the current timelock for adding new wards
    function delay() external view returns (uint256);

    /// @notice Returns when `relyTarget` has passed the timelock
    function schedule(address relyTarget) external view returns (uint256 timestamp);

    // --- Administration ---
    /// @notice Updates a contract parameter
    /// @param what Accepts a bytes32 representation of 'delay'
    function file(bytes32 what, uint256 data) external;

    /// --- Endorsements ---
    /// @notice Endorses the `user`
    /// @dev    Endorsed users are trusted contracts in the system. They are allowed to bypass
    ///         token restrictions (e.g. the Escrow can automatically receive tranche tokens by being endorsed), and
    ///         can automatically set operators in ERC-7540 vaults (e.g. the CentrifugeRouter) is always an operator.
    function endorse(address user) external;

    /// @notice Removes the endorsed user
    function veto(address user) external;

    /// @notice Returns whether the user is endorsed
    function endorsed(address user) external view returns (bool);

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
