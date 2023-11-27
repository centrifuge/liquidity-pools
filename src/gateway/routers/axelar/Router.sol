// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import {Auth} from "./../../../util/Auth.sol";

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
    string internal constant CENTRIFUGE_CHAIN_ID = "centrifuge";
    string internal constant CENTRIFUGE_CHAIN_ADDRESS = "0x7369626CEF070000000000000000000000000000";

    AxelarGatewayLike public immutable axelarGateway;
    string public centrifugeAxelarExecutable;

    GatewayLike public gateway;

    // --- Events ---
    event File(bytes32 indexed what, address addr);
    event File(bytes32 indexed what, string addr);

    constructor(address axelarGateway_, string memory centrifugeAxelarExecutable_) {
        axelarGateway = AxelarGatewayLike(axelarGateway_);
        centrifugeAxelarExecutable = centrifugeAxelarExecutable_;

        wards[msg.sender] = 1;
        emit Rely(msg.sender);
    }

    modifier onlyCentrifugeChainOrigin(string calldata sourceChain, string calldata sourceAddress) {
        require(
            keccak256(bytes(CENTRIFUGE_CHAIN_ID)) == keccak256(bytes(sourceChain)), "AxelarRouter/invalid-source-chain"
        );
        require(
            keccak256(bytes(CENTRIFUGE_CHAIN_ADDRESS)) == keccak256(bytes(sourceAddress)),
            "AxelarRouter/invalid-source-address"
        );
        _;
    }

    modifier onlyGateway() {
        require(msg.sender == address(gateway), "AxelarRouter/only-gateway-allowed-to-call");
        _;
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

    function file(bytes32 what, string memory data) external auth {
        if (what == "executable") {
            centrifugeAxelarExecutable = data;
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
    ) public onlyCentrifugeChainOrigin(sourceChain, sourceAddress) {
        bytes32 payloadHash = keccak256(payload);
        require(
            axelarGateway.validateContractCall(commandId, sourceChain, sourceAddress, payloadHash),
            "Router/not-approved-by-gateway"
        );

        gateway.handle(payload);
    }

    // --- Outgoing ---
    function send(bytes calldata message) public onlyGateway {
        axelarGateway.callContract(CENTRIFUGE_CHAIN_ID, centrifugeAxelarExecutable, message);
    }
}
