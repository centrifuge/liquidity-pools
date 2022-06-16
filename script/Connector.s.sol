// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.7.6;

import "forge-std/Script.sol";

import {ConnectorRouter} from "src/Router.sol";
import {CentrifugeConnector} from "src/Connector.sol";

contract ConnectorScript is Script {
    function setUp() public {}

    function run() public {
        vm.broadcast();
        ConnectorRouter router = new ConnectorRouter();
        new CentrifugeConnector(address(router));
    }
}
