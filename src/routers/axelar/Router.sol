// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.18;
pragma abicoder v2;

import {TypedMemView} from "memview-sol/TypedMemView.sol";
import {ConnectorMessages} from "../../Messages.sol";

interface ConnectorLike {
    function addPool(uint64 poolId) external;
    function addTranche(
        uint64 poolId,
        bytes16 trancheId,
        string memory tokenName,
        string memory tokenSymbol,
        uint128 price
    ) external;
    function updateMember(uint64 poolId, bytes16 trancheId, address user, uint64 validUntil) external;
    function updateTokenPrice(uint64 poolId, bytes16 trancheId, uint128 price) external;
    function handleTransferTrancheTokens(uint64 poolId, bytes16 trancheId, address destinationAddress, uint128 amount) external;
}

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
}

contract ConnectorAxelarRouter is AxelarExecutableLike {
    using TypedMemView for bytes;
    // why bytes29? - https://github.com/summa-tx/memview-sol#why-bytes29
    using TypedMemView for bytes29;
    using ConnectorMessages for bytes29;

    ConnectorLike public immutable connector;
    AxelarGatewayLike public immutable axelarGateway;

    string public constant axelarCentrifugeChainId = "Centrifuge";
    string public constant axelarCentrifugeChainAddress = "";

    constructor(address connector_, address axelarGateway_) {
        connector = ConnectorLike(connector_);
        axelarGateway = AxelarGatewayLike(axelarGateway_);
    }

    modifier onlyCentrifugeChainOrigin(string memory sourceChain) {
        require(
            msg.sender == address(axelarGateway)
                && keccak256(bytes(axelarCentrifugeChainId)) == keccak256(bytes(sourceChain)),
            "ConnectorAxelarRouter/invalid-origin"
        );
        _;
    }

    modifier onlyConnector() {
        require(msg.sender == address(connector), "ConnectorAxelarRouter/only-connector-allowed-to-call");
        _;
    }

    // --- Incoming ---
    function execute(bytes32, string calldata sourceChain, string calldata, bytes calldata payload)
        external
        onlyCentrifugeChainOrigin(sourceChain)
    {
        bytes29 _msg = payload.ref(0);

        if (ConnectorMessages.isAddPool(_msg)) {
            uint64 poolId = ConnectorMessages.parseAddPool(_msg);
            connector.addPool(poolId);
        } else if (ConnectorMessages.isAddTranche(_msg)) {
            (uint64 poolId, bytes16 trancheId, string memory tokenName, string memory tokenSymbol, uint128 price) =
                ConnectorMessages.parseAddTranche(_msg);
            connector.addTranche(poolId, trancheId, tokenName, tokenSymbol, price);
        } else if (ConnectorMessages.isUpdateMember(_msg)) {
            (uint64 poolId, bytes16 trancheId, address user, uint64 validUntil) =
                ConnectorMessages.parseUpdateMember(_msg);
            connector.updateMember(poolId, trancheId, user, validUntil);
        } else if (ConnectorMessages.isUpdateTrancheTokenPrice(_msg)) {
            (uint64 poolId, bytes16 trancheId, uint128 price) = ConnectorMessages.parseUpdateTrancheTokenPrice(_msg);
            connector.updateTokenPrice(poolId, trancheId, price);
        } else if (ConnectorMessages.isTransferTrancheTokens(_msg)) {
            (uint64 poolId, bytes16 trancheId,, address destinationAddress, uint128 amount) =
                ConnectorMessages.parseTransferTrancheTokens20(_msg);
            connector.handleTransferTrancheTokens(poolId, trancheId, destinationAddress, amount);
        } else {
            require(false, "invalid-message");
        }
    }

    // --- Outgoing ---
    function send(bytes memory message) public onlyConnector {
        axelarGateway.callContract(axelarCentrifugeChainId, axelarCentrifugeChainAddress, message);
    }
}
