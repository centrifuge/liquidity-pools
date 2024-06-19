// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.5.0;

interface IEscrow {
    // --- Events ---
    event Approve(address indexed token, address indexed spender, uint256 value);

    // --- Token approvals ---
    /// @notice TODO
    function approveMax(address token, address spender) external;

    /// @notice TODO
    function unapprove(address token, address spender) external;
}
