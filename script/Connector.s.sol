// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.7.6;

import "forge-std/Script.sol";

import {Router} from "src/Router.sol";
import {Connector} from "src/Connector.sol";

contract ConnectorScript is Script {
    function setUp() public {}

    function run() public {
        vm.broadcast();
        Router router = new Router();
        new Connector(address(router));
    }
}
