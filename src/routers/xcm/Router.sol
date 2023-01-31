// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.7.6;
pragma abicoder v2;

import {TypedMemView} from "memview-sol/TypedMemView.sol";
import {ConnectorMessages} from "../../Messages.sol";

interface ConnectorLike {
  function addPool(uint64 poolId) external;
  function addTranche(uint64 poolId, bytes16 trancheId, string memory tokenName, string memory tokenSymbol, uint128 price) external;
  function updateMember(uint64 poolId, bytes16 trancheId, address user, uint64 validUntil) external;
  function updateTokenPrice(uint64 poolId, bytes16 trancheId, uint128 price) external;
  function handleTransfer(uint64 poolId, bytes16 trancheId, address user, uint256 amount) external;
}

contract ConnectorXCMRouter {
    using TypedMemView for bytes;
    // why bytes29? - https://github.com/summa-tx/memview-sol#why-bytes29
    using TypedMemView for bytes29;
    using ConnectorMessages for bytes29;

    ConnectorLike public immutable connector;

    address centrifugeChainOrigin;

    constructor(address connector_, address centrifugeChainOrigin_) {
        connector = ConnectorLike(connector_);
        centrifugeChainOrigin = centrifugeChainOrigin_;
    }
    
   
    modifier onlyCentrifugeChainOrigin() {
        require(msg.sender == address(centrifugeChainOrigin), "ConnectorXCMRouter/invalid-origin");
        _;
    }

    modifier onlyConnector() {
        require(msg.sender == address(connector), "ConnectorXCMRouter/only-connector-allowed-to-call");
        _;
    }

    function handle(
        bytes memory _message
    ) external onlyCentrifugeChainOrigin {
        bytes29 _msg = _message.ref(0);
        if (ConnectorMessages.isAddPool(_msg)) {
            uint64 poolId = ConnectorMessages.parseAddPool(_msg);
            connector.addPool(poolId);
        } else if (ConnectorMessages.isAddTranche(_msg)) {
            (uint64 poolId, bytes16 trancheId, string memory tokenName, string memory tokenSymbol, uint128 price) = ConnectorMessages.parseAddTranche(_msg);
            connector.addTranche(poolId, trancheId, tokenName, tokenSymbol, price);
        } else if (ConnectorMessages.isUpdateMember(_msg)) {
            (uint64 poolId, bytes16 trancheId, address user, uint64 validUntil) = ConnectorMessages.parseUpdateMember(_msg);
            connector.updateMember(poolId, trancheId, user, validUntil);
        } else if (ConnectorMessages.isUpdateTokenPrice(_msg)) {
            (uint64 poolId, bytes16 trancheId, uint128 price) = ConnectorMessages.parseUpdateTokenPrice(_msg);
            connector.updateTokenPrice(poolId, trancheId, price);
        } else if (ConnectorMessages.isTransfer(_msg)) {
            (uint64 poolId, bytes16 trancheId, address user, uint256 amount) = ConnectorMessages.parseTransfer(_msg);
            connector.handleTransfer(poolId, trancheId, user, amount);
        } else {
            require(false, "invalid-message");
        }
    }

    function sendMessage(uint32 destinationDomain, uint64 poolId, bytes16 trancheId, uint256 amount, address user) external onlyConnector {
        // TODO: implement
    }

    function bytes32ToString(bytes32 _bytes32) internal pure returns (string memory) {
        uint8 i = 0;
        while (i < 32 && _bytes32[i] != 0) {
            i++;
        }

        bytes memory bytesArray = new bytes(i);
        for (i = 0; i < 32 && _bytes32[i] != 0; i++) {
            bytesArray[i] = _bytes32[i];
        }
        return string(bytesArray);
    }

}
