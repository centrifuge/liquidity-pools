// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.7.6;

import { ConnectorNomadRouter } from "src/routers/nomad/Router.sol";
import { CentrifugeConnector } from "src/Connector.sol";
import { RestrictedTokenFactory, MemberlistFactory } from "src/token/factory.sol";
import "forge-std/Script.sol";

// Script to deploy Connectors with a Nomad router.
contract ConnectorNomadScript is Script {
    function setUp() public {}

    function run() public {
        vm.broadcast();

        address tokenFactory_ = address(new RestrictedTokenFactory());
        address memberlistFactory_ = address(new MemberlistFactory());
        CentrifugeConnector connector = new CentrifugeConnector(tokenFactory_, memberlistFactory_);

        // TODO: pass _xAppConnectionManager as 2nd argument
        ConnectorNomadRouter router = new ConnectorNomadRouter(address(connector), address(0));
        connector.file("router", address(router));
    }
}
