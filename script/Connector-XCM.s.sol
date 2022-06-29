// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.7.6;

import { ConnectorXCMRouter } from "src/routers/xcm/Router.sol";
import { CentrifugeConnector } from "src/Connector.sol";
import { RestrictedTokenFactory, MemberlistFactory } from "src/token/factory.sol";
import "forge-std/Script.sol";

contract ConnectorXCMScript is Script {
    function setUp() public {}

    function run() public {
        vm.broadcast();

        address tokenFactory_ = address(new RestrictedTokenFactory());
        address memberlistFactory_ = address(new MemberlistFactory());
        address connector = new CentrifugeConnector(tokenFactory_, memberlistFactory_);

        // TODO: add centrifugeChainOrigin_ arg
        ConnectorRouter router = new ConnectorXCMRouter(connector, address(0));
        connector.file("router", router);
    }
}
