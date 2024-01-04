// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import {Auth} from "./../../../Auth.sol";

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

interface GatewayLike {
    function handle(bytes memory message) external;
}

/// @title  Axelar Router
/// @notice Routing contract that integrates with an Axelar Gateway
contract AxelarRouter is Auth {
    string public constant CENTRIFUGE_CHAIN_ID = "centrifuge";
    bytes32 public constant CENTRIFUGE_CHAIN_ID_HASH = keccak256(bytes("centrifuge"));
    bytes32 public constant CENTRIFUGE_CHAIN_ADDRESS_HASH =
        keccak256(bytes("0x7369626CEF070000000000000000000000000000"));
    string public constant CENTRIFUGE_AXELAR_EXECUTABLE = "0xc1757c6A0563E37048869A342dF0651b9F267e41";

    AxelarGatewayLike public immutable axelarGateway;

    GatewayLike public gateway;

    // --- Events ---
    event File(bytes32 indexed what, address addr);

    constructor(address axelarGateway_) {
        axelarGateway = AxelarGatewayLike(axelarGateway_);

        wards[msg.sender] = 1;
        emit Rely(msg.sender);
    }

    // --- Administration ---
    function file(bytes32 what, address data) external auth {
        if (what == "gateway") {
            gateway = GatewayLike(data);
        } else {
            revert("AxelarRouter/file-unrecognized-param");
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
        require(keccak256(bytes(sourceChain)) == CENTRIFUGE_CHAIN_ID_HASH, "AxelarRouter/invalid-source-chain");
        require(keccak256(bytes(sourceAddress)) == CENTRIFUGE_CHAIN_ADDRESS_HASH, "AxelarRouter/invalid-source-address");

        bytes32 payloadHash = keccak256(payload);
        require(
            axelarGateway.validateContractCall(commandId, sourceChain, sourceAddress, payloadHash),
            "Router/not-approved-by-gateway"
        );

        gateway.handle(payload);
    }

    // --- Outgoing ---
    function send(bytes calldata message) public {
        require(msg.sender == address(gateway), "AxelarRouter/only-gateway-allowed-to-call");
        axelarGateway.callContract(CENTRIFUGE_CHAIN_ID, CENTRIFUGE_AXELAR_EXECUTABLE, message);
    }
}
