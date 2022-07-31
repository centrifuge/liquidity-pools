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
        vm.startBroadcast();

        address tokenFactory_ = address(new RestrictedTokenFactory());
        address memberlistFactory_ = address(new MemberlistFactory());
        CentrifugeConnector connector = new CentrifugeConnector(tokenFactory_, memberlistFactory_);

        // TODO: add centrifugeChainOrigin_ arg. Using Kovan Admin Account in the meantime
        ConnectorXCMRouter router = new ConnectorXCMRouter(address(connector), address(0x0A735602a357802f553113F5831FE2fbf2F0E2e0));
        connector.file("router", address(router));
        vm.stopBroadcast();
    }
}
