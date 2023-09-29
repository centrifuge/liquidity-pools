// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import {Auth} from "../../../util/Auth.sol";

interface AxelarGatewayLike {
    function validateContractCall(
        bytes32 commandId,
        string calldata sourceChain,
        string calldata sourceAddress,
        bytes32 payloadHash
    ) external returns (bool);
}

interface PrecompileLike {
    function execute(
        bytes32 commandId,
        string calldata sourceChain,
        string calldata sourceAddress,
        bytes calldata payload
    ) external;
}

// A contract to be deployed on Centrifuge-EVM in order to forward axelar tx to
// the precompile.
contract PassthroughGateway is Auth {
    // --- Events ---
    event Validated(bytes32 commandId, string sourceChain, string sourceAddress, bytes32 payload);

    constructor() {
        wards[msg.sender] = 1;
        emit Rely(msg.sender);
    }

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
