// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.7.6;

import "forge-std/Test.sol";
import {Router} from "@nomad-xyz/contracts-router/contracts/Router.sol";

contract ConnectorRouter is Router, Test {
    uint32 immutable CENTRIFUGE_CHAIN_DOMAIN = 3000;

    function updateInvestOrder(
        uint256 poolId,
        uint256[] calldata trancheId,
        uint256 amount
    ) external {
        console.log(poolId);
        console.log(amount);
        // TODO: send message to Nomad Home contract
        return;
    }

    function send(bytes memory message) internal {
        (_home()).dispatch(
            CENTRIFUGE_CHAIN_DOMAIN,
            _mustHaveRemote(CENTRIFUGE_CHAIN_DOMAIN),
            message
        );
    }

    function handle(
        uint32,
        uint32,
        bytes32,
        bytes memory _message
    ) external override {
        console.log("handle called");
        console.log(string(_message));
    }
}
