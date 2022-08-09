// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.7.6;

import { ConnectorXCMRouter } from "src/routers/xcm/Router.sol";
import { CentrifugeConnector } from "src/Connector.sol";
import { RestrictedTokenFactory, MemberlistFactory } from "src/token/factory.sol";
import "forge-std/Script.sol";

// Script to deploy Connectors with an XCM router.
contract ConnectorXCMScript is Script {
    function setUp() public {}

    function run() public {
        vm.broadcast();

        address tokenFactory_ = address(new RestrictedTokenFactory());
        address memberlistFactory_ = address(new MemberlistFactory());
        CentrifugeConnector connector = new CentrifugeConnector(tokenFactory_, memberlistFactory_);

        // TODO: add centrifugeChainOrigin_ arg
        ConnectorXCMRouter router = new ConnectorXCMRouter(address(connector), address(0), address(0));
        connector.file("router", address(router));
    }
}
