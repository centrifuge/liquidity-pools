// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.5.0;

interface IEscrow {
    // --- Events ---
    event Approve(address indexed token, address indexed spender, uint256 value);

    // --- Token approvals ---
    /// @notice TODO
    function approve(address token, address spender, uint256 value) external;
}
