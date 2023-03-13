// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.18;
pragma abicoder v2;

import {TypedMemView} from "memview-sol/TypedMemView.sol";
import {ConnectorMessages} from "src/Messages.sol";
import "forge-std/Test.sol";
import {ConnectorXCMRouter} from "src/routers/xcm/Router.sol";

interface XcmRouterLike {
    function handle(bytes memory _message) external;
    function send(bytes memory message) external;
}

contract MockHomeConnector is Test {
    using TypedMemView for bytes;
    using TypedMemView for bytes29;
    using ConnectorMessages for bytes29;

    XcmRouterLike public immutable router;

    uint32 immutable CENTRIFUGE_CHAIN_DOMAIN = 3000;
    uint32 immutable NONCE = 1;

    uint32 public dispatchDomain;
    bytes public dispatchMessage;
    bytes32 public dispatchRecipient;
    uint256 public dispatchCalls;

    enum Types {AddPool}

    constructor(address xcmRouter) {
        router = XcmRouterLike(xcmRouter);
    }

    function addPool(uint64 poolId) public {
        bytes memory _message = ConnectorMessages.formatAddPool(poolId);
        router.handle(_message);
    }

    function addTranche(
        uint64 poolId,
        bytes16 trancheId,
        string memory tokenName,
        string memory tokenSymbol,
        uint128 price
    ) public {
        bytes memory _message = ConnectorMessages.formatAddTranche(poolId, trancheId, tokenName, tokenSymbol, price);
        router.handle(_message);
    }

    function updateMember(uint64 poolId, bytes16 trancheId, address user, uint64 validUntil) public {
        bytes memory _message = ConnectorMessages.formatUpdateMember(poolId, trancheId, user, validUntil);
        router.handle(_message);
    }

    function updateTokenPrice(uint64 poolId, bytes16 trancheId, uint128 price) public {
        bytes memory _message = ConnectorMessages.formatUpdateTokenPrice(poolId, trancheId, price);
        router.handle(_message);
    }

    // Triggger an incoming (e.g. Centrifuge Chain -> EVM) transfer
    function transfer(
        uint64 poolId,
        bytes16 trancheId,
        bytes9 destinationDomain,
        address destinationAddress,
        uint128 amount
    ) public {
        bytes memory _message =
            ConnectorMessages.formatTransfer(poolId, trancheId, destinationDomain, destinationAddress, amount);
        router.handle(_message);
    }

    function dispatch(uint32 _destinationDomain, bytes32 _recipientAddress, bytes memory _messageBody) external {
        dispatchCalls++;
        dispatchDomain = _destinationDomain;
        dispatchMessage = _messageBody;
        dispatchRecipient = _recipientAddress;
    }
}
