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
