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

    // Used to recover any ERC-20 token.
    // Following this spec https://eips.ethereum.org/EIPS/eip-7528 
    // the token address could be 0xeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee
    // to recover locked native ETH.
    function recoverTokens(address token, address to, uint256 amount) external;
}
