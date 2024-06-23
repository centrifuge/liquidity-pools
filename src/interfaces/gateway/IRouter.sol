// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.5.0;

interface IRouter {
    // --- Incoming ---
    /// @notice TODO
    function execute(
        bytes32 commandId,
        string calldata sourceChain,
        string calldata sourceAddress,
        bytes calldata payload
    ) external;

    // --- Outgoing ---
    /// @notice TODO
    function send(bytes calldata payload) external;
}
