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
    function handleTransfer(uint64 poolId, bytes16 trancheId, address destinationAddress, uint128 amount) external;
}

interface ChainBridgeLike {
    function deposit(uint8 destinationChainID, bytes32 resourceID, bytes calldata data) external payable;
}

interface ChainBridgeDepositExecuteLike {
    function executeProposal(bytes32 resourceID, bytes calldata data) external;
}

contract ConnectorChainBridgeRouter is ChainBridgeDepositExecuteLike {
    using TypedMemView for bytes;
    // why bytes29? - https://github.com/summa-tx/memview-sol#why-bytes29
    using TypedMemView for bytes29;
    using ConnectorMessages for bytes29;

    ConnectorLike public immutable connector;
    ChainBridgeLike public immutable bridge;

    uint256 public constant deposit = 0.01 ether;
    string public constant centrifugeChainId = "Centrifuge";
    string public constant resourceID = "TODO";

    constructor(address connector_, address bridge_) {
        connector = ConnectorLike(connector_);
        bridge = ChainBridgeLike(bridge_);
    }

    modifier onlyChainBridgeOrigin() {
        require(
            msg.sender == address(bridge),
            "ConnectorChainBridgeRouter/invalid-origin"
        );
        _;
    }

    modifier onlyConnector() {
        require(msg.sender == address(connector), "ConnectorChainBridgeRouter/only-connector-allowed-to-call");
        _;
    }

    // --- Incoming ---
    function executeProposal(bytes32, bytes calldata payload)
        external
        onlyChainBridgeOrigin
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
        } else if (ConnectorMessages.isUpdateTokenPrice(_msg)) {
            (uint64 poolId, bytes16 trancheId, uint128 price) = ConnectorMessages.parseUpdateTokenPrice(_msg);
            connector.updateTokenPrice(poolId, trancheId, price);
        } else if (ConnectorMessages.isTransfer(_msg)) {
            (uint64 poolId, bytes16 trancheId,, address destinationAddress, uint128 amount) =
                ConnectorMessages.parseTransfer20(_msg);
            connector.handleTransfer(poolId, trancheId, destinationAddress, amount);
        } else {
            require(false, "invalid-message");
        }
    }

    // --- Outgoing ---
    function send(bytes memory message) public onlyConnector {
        bridge.deposit(centrifugeChainId, resourceID, message);
    }
}
