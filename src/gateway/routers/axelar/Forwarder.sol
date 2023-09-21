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

contract AxelarForwarder is Auth {
    PrecompileLike public constant precompile = PrecompileLike(0x0000000000000000000000000000000000000800);

    AxelarGatewayLike public axelarGateway;

    // --- Events ---
    event File(bytes32 indexed what, address data);
    event Forwarded(bytes32 commandId, string sourceChain, string sourceAddress, bytes payload);

    constructor(address axelarGateway_) {
        axelarGateway = AxelarGatewayLike(axelarGateway_);

        wards[msg.sender] = 1;
        emit Rely(msg.sender);
    }

    // --- Administration ---
    function file(bytes32 what, address data) external auth {
        if (what == "axelarGateway") {
            axelarGateway = AxelarGatewayLike(data);
        } else {
            revert("AxelarForwarder/file-unrecognized-param");
        }

        emit File(what, data);
    }

    // --- Incoming ---
    function execute(
        bytes32 commandId,
        string calldata sourceChain,
        string calldata sourceAddress,
        bytes calldata payload
    ) public {
        require(
            axelarGateway.validateContractCall(commandId, sourceChain, sourceAddress, keccak256(payload)),
            "AxelarForwarder/not-approved-by-gateway"
        );

        precompile.execute(commandId, sourceChain, sourceAddress, payload);

        emit Forwarded(commandId, sourceChain, sourceAddress, payload);
    }

    function executeWithToken(
        bytes32 commandId,
        string calldata sourceChain,
        string calldata sourceAddress,
        bytes calldata payload,
        string calldata tokenSymbol,
        uint256 amount
    ) internal {
        revert("AxelarForwarder/execute-with-token-not-supported");
    }
}
