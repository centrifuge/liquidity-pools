// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.18;

interface AxelarExecutableLike {
    function execute(
        bytes32 commandId,
        string calldata sourceChain,
        string calldata sourceAddress,
        bytes calldata payload
    ) external;
}

interface AxelarGatewayLike {
    function callContract(string calldata destinationChain, string calldata contractAddress, bytes calldata payload)
        external;

    function validateContractCall(
        bytes32 commandId,
        string calldata sourceChain,
        string calldata sourceAddress,
        bytes32 payloadHash
    ) external returns (bool);
}

/**
 * Source: https://github.com/axelarnetwork/axelar-gmp-sdk-solidity/blob/main/contracts/executable/AxelarExecutable.sol
 */
contract AxelarExecutable is AxelarExecutableLike {
    AxelarGatewayLike public immutable axelarGateway;

    constructor(address axelarGateway_) {
        require(axelarGateway_ != address(0), "AxelarExecutable/invalid-address");

        axelarGateway = AxelarGatewayLike(axelarGateway_);
    }

    function execute(
        bytes32 commandId,
        string calldata sourceChain,
        string calldata sourceAddress,
        bytes calldata payload
    ) external {
        bytes32 payloadHash = keccak256(payload);
        require(
            axelarGateway.validateContractCall(commandId, sourceChain, sourceAddress, payloadHash),
            "AxelarExecutable/not-approved-by-gateway"
        );

        _execute(sourceChain, sourceAddress, payload);
    }

    function _execute(string calldata sourceChain, string calldata sourceAddress, bytes calldata payload)
        internal
        virtual
    {}
}
