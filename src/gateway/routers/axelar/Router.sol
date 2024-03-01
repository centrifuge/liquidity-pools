// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

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

interface AxelarGasServiceLike {
    function payNativeGasForContractCall(
        address sender,
        string calldata destinationChain,
        string calldata destinationAddress,
        bytes calldata payload,
        address refundAddress
    ) external payable;
}

interface AggregatorLike {
    function handle(bytes memory message) external;
}

/// @title  Axelar Router
/// @notice Routing contract that integrates with an Axelar Gateway
contract AxelarRouter {
    string public constant CENTRIFUGE_ID = "centrifuge";
    bytes32 public constant CENTRIFUGE_ID_HASH = keccak256(bytes("centrifuge"));
    bytes32 public constant CENTRIFUGE_ADDRESS_HASH = keccak256(bytes("0x7369626CEF070000000000000000000000000000"));
    string public constant CENTRIFUGE_AXELAR_EXECUTABLE = "0xc1757c6A0563E37048869A342dF0651b9F267e41";

    AggregatorLike public immutable aggregator;
    AxelarGatewayLike public immutable axelarGateway;
    AxelarGasServiceLike public immutable axelarGasService;

    constructor(address aggregator_, address axelarGateway_, address axelarGasService_) {
        aggregator = AggregatorLike(aggregator_);
        axelarGateway = AxelarGatewayLike(axelarGateway_);
        axelarGasService = AxelarGasServiceLike(axelarGasService_);
    }

    // --- Incoming ---
    function execute(
        bytes32 commandId,
        string calldata sourceChain,
        string calldata sourceAddress,
        bytes calldata payload
    ) public {
        require(keccak256(bytes(sourceChain)) == CENTRIFUGE_ID_HASH, "AxelarRouter/invalid-source-chain");
        require(keccak256(bytes(sourceAddress)) == CENTRIFUGE_ADDRESS_HASH, "AxelarRouter/invalid-source-address");
        require(
            axelarGateway.validateContractCall(commandId, sourceChain, sourceAddress, keccak256(payload)),
            "AxelarRouter/not-approved-by-axelar-gateway"
        );

        aggregator.handle(payload);
    }

    // --- Outgoing ---
    function estimate(uint256 baseCost) public returns (uint256) {
        return baseCost; 
    }

    // TODO: is there any risk with this being public and having a sender arg?
    function pay(address sender, bytes calldata payload) public payable {
        axelarGasService.payNativeGasForContractCall{value: msg.value}(
            sender, CENTRIFUGE_ID, CENTRIFUGE_AXELAR_EXECUTABLE, payload, sender
        );
    }

    function send(bytes calldata paypload) public {
        require(msg.sender == address(aggregator), "AxelarRouter/only-aggregator-allowed-to-call");

        axelarGateway.callContract(CENTRIFUGE_ID, CENTRIFUGE_AXELAR_EXECUTABLE, paypload);
    }
}
