// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import {IAdapter} from "src/interfaces/gateway/IAdapter.sol";
import {Auth} from "src/Auth.sol";

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

interface AxelarGasServiceLike {
    function payNativeGasForContractCall(
        address sender,
        string calldata destinationChain,
        string calldata destinationAddress,
        bytes calldata payload,
        address refundAddress
    ) external payable;
}

/// @title  Axelar Adapter
/// @notice Routing contract that integrates with an Axelar Gateway
contract AxelarAdapter is Auth, IAdapter {
    string public constant CENTRIFUGE_ID = "centrifuge";
    bytes32 public constant CENTRIFUGE_ID_HASH = keccak256(bytes("centrifuge"));
    bytes32 public constant CENTRIFUGE_ADDRESS_HASH = keccak256(bytes("0x7369626CEF070000000000000000000000000000"));
    string public constant CENTRIFUGE_AXELAR_EXECUTABLE = "0xc1757c6A0563E37048869A342dF0651b9F267e41";

    GatewayLike public immutable gateway;
    AxelarGatewayLike public immutable axelarGateway;
    AxelarGasServiceLike public immutable axelarGasService;

    /// @dev This value is in AXELAR fees in ETH ( wei )
    uint256 axelarCost = 58039058122843;

    constructor(address gateway_, address axelarGateway_, address axelarGasService_) {
        gateway = GatewayLike(gateway_);
        axelarGateway = AxelarGatewayLike(axelarGateway_);
        axelarGasService = AxelarGasServiceLike(axelarGasService_);

        wards[msg.sender] = 1;
        emit Rely(msg.sender);
    }

    // --- Administrative ---
    function file(bytes32 what, uint256 value) external auth {
        if (what == "axelarCost") axelarCost = value;
        else revert("AxelarAdapterfile-unrecognized-param");
        emit File(what, value);
    }
    // --- Incoming ---
    /// @inheritdoc IAdapter

    function execute(
        bytes32 commandId,
        string calldata sourceChain,
        string calldata sourceAddress,
        bytes calldata payload
    ) public {
        require(keccak256(bytes(sourceChain)) == CENTRIFUGE_ID_HASH, "AxelarAdapter/invalid-source-chain");
        require(keccak256(bytes(sourceAddress)) == CENTRIFUGE_ADDRESS_HASH, "AxelarAdapter/invalid-source-address");
        require(
            axelarGateway.validateContractCall(commandId, sourceChain, sourceAddress, keccak256(payload)),
            "AxelarAdapter/not-approved-by-axelar-gateway"
        );

        gateway.handle(payload);
    }

    // --- Outgoing ---
    /// @inheritdoc IAdapter
    function send(bytes calldata payload) public {
        require(msg.sender == address(gateway), "AxelarAdapter/only-gateway-allowed-to-call");

        axelarGateway.callContract(CENTRIFUGE_ID, CENTRIFUGE_AXELAR_EXECUTABLE, payload);
    }

    function pay(bytes calldata payload, address refund) public payable {
        axelarGasService.payNativeGasForContractCall{value: msg.value}(
            address(this), CENTRIFUGE_ID, CENTRIFUGE_AXELAR_EXECUTABLE, payload, refund
        );
    }

    /// @dev Currently the payload ( message ) is not taken into consideration during cost estimation
    /// A predefined `axelarCost` value is used.
    function estimate(bytes calldata, uint256 gasLimit) public view returns (uint256) {
        return axelarCost + gasLimit;
    }
}
