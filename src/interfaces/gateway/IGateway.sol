// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.5.0;

interface IGateway {
    // --- Events ---
    event File(bytes32 indexed what, address data);
    event File(bytes32 indexed what, uint8 messageId, address manager);

    // --- Administration ---
    /// @notice TODO
    function file(bytes32 what, address data) external;

    /// @notice TODO
    function file(bytes32 what, uint8 data1, address data2) external;

    // --- Outgoing ---
    /// @notice TODO
    function send(bytes calldata message) external payable;

    // --- Incoming ---
    /// @notice TODO
    function handle(bytes calldata message) external;
}
