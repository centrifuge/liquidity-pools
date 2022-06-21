// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.7.6;

import { ConnectorRouter } from "src/routers/nomad/Router.sol";
import { CentrifugeConnector } from "src/Connector.sol";
import { RestrictedTokenFactory, MemberlistFactory } from "src/token/factory.sol";
import "forge-std/Script.sol";

contract ConnectorScript is Script {
    function setUp() public {}

    function run() public {
        vm.broadcast();

        address tokenFactory_ = address(new RestrictedTokenFactory());
        address memberlistFactory_ = address(new MemberlistFactory());
        ConnectorRouter router = new ConnectorRouter(address(0));

        new CentrifugeConnector(address(router), tokenFactory_, memberlistFactory_);

        // TODO:  file connector on router
    }
}
