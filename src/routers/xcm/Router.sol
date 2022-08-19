// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.7.6;
pragma abicoder v2;

import {TypedMemView} from "@summa-tx/memview-sol/contracts/TypedMemView.sol";
import {Router} from "@nomad-xyz/contracts-router/contracts/Router.sol";
import {Home} from "@nomad-xyz/contracts-core/contracts/Home.sol";
import {ConnectorMessages} from "../..//Messages.sol";
import "forge-std/Test.sol";

interface ConnectorLike {
  function addPool(uint64 poolId) external;
  function addTranche(uint64 poolId, bytes16 trancheId, string memory tokenName, string memory tokenSymbol) external;
  function updateMember(uint64 poolId, bytes16 trancheId, address user, uint256 validUntil) external;
  function updateTokenPrice(uint64 poolId, bytes16 trancheId, uint256 price) external;
  function transfer(uint64 poolId, bytes16 trancheId, address user, uint256 amount) external;
}

contract ConnectorXCMRouter is Router, Test {
    using TypedMemView for bytes;
    // why bytes29? - https://github.com/summa-tx/memview-sol#why-bytes29
    using TypedMemView for bytes29;
    using ConnectorMessages for bytes29;

    ConnectorLike public immutable connector;

    address immutable centrifugeChainOrigin;

    constructor(address connector_, address centrifugeChainOrigin_, address xAppConnectionManager) {
        connector = ConnectorLike(connector_);
        centrifugeChainOrigin = centrifugeChainOrigin_;

        __Ownable_init();
        __XAppConnectionClient_initialize(xAppConnectionManager);
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
        uint32 _origin,
        uint32 _nonce,
        bytes32 _sender,
        bytes memory _message
    ) external override onlyCentrifugeChainOrigin {
        bytes29 _msg = _message.ref(0);
        if (ConnectorMessages.isAddPool(_msg) == true) {
            uint64 poolId = ConnectorMessages.parseAddPool(_msg);
            connector.addPool(poolId);
        } else if (ConnectorMessages.isAddTranche(_msg) == true) {
            (uint64 poolId, bytes16 trancheId, string memory tokenName, string memory tokenSymbol) = ConnectorMessages.parseAddTranche(_msg);
            connector.addTranche(poolId, trancheId, tokenName, tokenSymbol);
        } else if (ConnectorMessages.isUpdateMember(_msg) == true) {
            (uint64 poolId, bytes16 trancheId, address user, uint256 validUntil) = ConnectorMessages.parseUpdateMember(_msg);
            connector.updateMember(poolId, trancheId, user, validUntil);
        } else if (ConnectorMessages.isUpdateTokenPrice(_msg) == true) {
            (uint64 poolId, bytes16 trancheId, uint256 price) = ConnectorMessages.parseUpdateTokenPrice(_msg);
            connector.updateTokenPrice(poolId, trancheId, price);
        } else if (ConnectorMessages.isTransfer(_msg) == true) {
            (uint64 poolId, bytes16 trancheId, address user, uint256 amount) = ConnectorMessages.parseTransfer(_msg);
            connector.transfer(poolId, trancheId, user, amount);
        } else {
            require(false, "invalid-message");
        }
    }

    function sendMessage(uint32 destinationDomain, uint64 poolId, bytes16 trancheId, uint256 amount, address user) external onlyConnector {
        bytes32 remoteAddress = _mustHaveRemote(destinationDomain);
        Home(xAppConnectionManager.home()).dispatch(
            destinationDomain,
            remoteAddress,
            ConnectorMessages.formatTransfer(poolId, trancheId, user, amount));
    }

       function bytes32ToString(bytes32 _bytes32) internal returns (string memory) {
        uint8 i = 0;
        while(i < 32 && _bytes32[i] != 0) {
            i++;
        }

        bytes memory bytesArray = new bytes(i);
        for (i = 0; i < 32 && _bytes32[i] != 0; i++) {
            bytesArray[i] = _bytes32[i];
        }
        return string(bytesArray);
    }

}
