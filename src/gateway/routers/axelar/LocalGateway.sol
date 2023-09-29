// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

interface AxelarGatewayLike {
    function validateContractCall(
        bytes32 commandId,
        string calldata sourceChain,
        string calldata sourceAddress,
        bytes32 payloadHash
    ) external returns (bool);
}

// A contract to be deployed on Centrifuge-EVM in order to forward axelar tx to
// the precompile.
contract PassthroughGateway {
    // --- Events ---
    event Validated(bytes32 commandId, string sourceChain, string sourceAddress, bytes32 payload);

    function validateContractCall(
        bytes32 commandId,
        string calldata sourceChain,
        string calldata sourceAddress,
        bytes32 payloadHash
    ) external returns (bool) {
        emit Validated(commandId, sourceChain, sourceAddress, payloadHash);

        return true;
    }
}
