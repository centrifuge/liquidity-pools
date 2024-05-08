// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

interface IEscrow {
    // --- Events ---
    event Approve(address indexed token, address indexed spender, uint256 value);

    // --- Token approvals ---
    /// @notice TODO
    function approve(address token, address spender, uint256 value) external;
}
