// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.5.0;

interface IRouter {
    event File(bytes32 what, uint256 value);

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

    /// @notice TODO
    function estimate(bytes calldata payload, uint256 destChainCost) external returns (uint256);

    /// @notice TODO
    function pay(bytes calldata payload, address refund) external payable;
}
