// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.7.6;
pragma abicoder v2;

import {TypedMemView} from "memview-sol/TypedMemView.sol";
import "forge-std/Test.sol";
import {CentrifugeConnector} from "src/Connector.sol";
import {ConnectorMessages} from "src/Messages.sol";

contract MockXcmRouter is Test {
    using TypedMemView for bytes;
    using TypedMemView for bytes29;

    CentrifugeConnector public immutable connector;

    constructor(CentrifugeConnector connector_) {
        connector = connector_;
    }

    modifier onlyConnector() {
        require(msg.sender == address(connector), "ConnectorXCMRouter/only-connector-allowed-to-call");
        _;
    }

    function handle(bytes memory _message) external {
        bytes29 _msg = _message.ref(0);
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
                ConnectorMessages.parseTransfer(_msg);
            connector.handleTransfer(poolId, trancheId, destinationAddress, amount);
        } else {
            require(false, "invalid-message");
        }
    }

    function send(bytes memory message) public onlyConnector {
        // do nothing
    }
}
