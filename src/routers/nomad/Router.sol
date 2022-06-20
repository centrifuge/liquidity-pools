// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.7.6;
pragma abicoder v2;

import {TypedMemView} from "@summa-tx/memview-sol/contracts/TypedMemView.sol";
import {Router} from "@nomad-xyz/contracts-router/contracts/Router.sol";
import {ConnectorMessages} from "../..//Messages.sol";
import "forge-std/Test.sol";

interface ConnectorLike {
  function addPool(uint64 poolId) external;
}

contract ConnectorRouter is Router, Test {
    using TypedMemView for bytes;
    using TypedMemView for bytes29;
    using ConnectorMessages for bytes29;

    ConnectorLike public immutable connector;

    uint32 immutable CENTRIFUGE_CHAIN_DOMAIN = 3000;

    constructor(address connector_) {
        connector = ConnectorLike(connector_);
    }

    function updateInvestOrder(
        uint256 poolId,
        uint256[] calldata trancheId,
        uint256 amount
    ) external {
        console.log(poolId);
        console.log(amount);
        // TODO: send message to Nomad Home contract by calling send()
        return;
    }

    function send(bytes memory message) internal {
        (_home()).dispatch(
            CENTRIFUGE_CHAIN_DOMAIN,
            _mustHaveRemote(CENTRIFUGE_CHAIN_DOMAIN),
            message
        );
    }

    // TODO: onlyReplica onlyRemoteRouter(_origin, _sender) 
    function handle(
        uint32 _origin,
        uint32 _nonce,
        bytes32 _sender,
        bytes memory _message
    ) external override {
        bytes29 _msg = _message.ref(0);
        if (ConnectorMessages.isAddPool(_msg) == true) {
            uint64 poolId = ConnectorMessages.parseAddPool(_msg);
            console.log(poolId);
            connector.addPool(poolId);
        } else {
            require(false, "invalid-message");
        }
    }
}
