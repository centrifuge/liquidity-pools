// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.7.6;
pragma abicoder v2;

import {TypedMemView} from "memview-sol/TypedMemView.sol";
import {ConnectorMessages} from "src/Messages.sol";
import "forge-std/Test.sol";
import { ConnectorXCMRouter } from "src/routers/xcm/Router.sol";

contract MockHomeConnector is Test {
    using TypedMemView for bytes;
    using TypedMemView for bytes29;
    using ConnectorMessages for bytes29;

    ConnectorXCMRouter public immutable router;

    uint32 immutable CENTRIFUGE_CHAIN_DOMAIN = 3000;
    uint32 immutable NONCE = 1;


    uint32 public dispatchDomain;
    bytes public dispatchMessage;
    bytes32 public dispatchRecipient;
    uint public dispatchCalls;


    enum Types {
        AddPool
    }

    constructor(address bridgedConnector) {
        router = new ConnectorXCMRouter(bridgedConnector, address(this));
    }

    function addPool(uint64 poolId) public {
        bytes memory _message = ConnectorMessages.formatAddPool(poolId);
        router.handle(_message);
    }

    function addTranche(uint64 poolId, bytes16 trancheId, string memory tokenName, string memory tokenSymbol) public {
        bytes memory _message = ConnectorMessages.formatAddTranche(poolId, trancheId, tokenName, tokenSymbol);
        router.handle(_message);
    }

    function updateMember(uint64 poolId, bytes16 trancheId, address user, uint256 amount) public {
        bytes memory _message = ConnectorMessages.formatUpdateMember(poolId, trancheId, user, amount);
        router.handle(_message);
    }

    function updateTokenPrice(uint64 poolId, bytes16 trancheId, uint256 price) public {
        bytes memory _message = ConnectorMessages.formatUpdateTokenPrice(poolId, trancheId, price);
        router.handle(_message);
    }

    function transfer(uint64 poolId, bytes16 trancheId, address user, uint256 amount) public  {
        bytes memory _message = ConnectorMessages.formatTransfer(poolId, trancheId, user, amount);
        router.handle(_message);
    }


    function dispatch(
        uint32 _destinationDomain,
        bytes32 _recipientAddress,
        bytes memory _messageBody
    ) external {
         dispatchCalls++;
         dispatchDomain = _destinationDomain;
         dispatchMessage =  _messageBody;
         dispatchRecipient = _recipientAddress;
    }

}
