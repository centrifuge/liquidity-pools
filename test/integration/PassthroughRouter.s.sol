// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import {Deployer, RouterLike} from "../../script/Deployer.sol";
import {PassthroughRouter} from "./PassthroughRouter.sol";

contract PassthroughRouterScript is Deployer {
    function setUp() public {}

    function run() public {
        vm.startBroadcast();
        deploy(msg.sender);
        PassthroughRouter router = new PassthroughRouter(msg.sender);
        adminSafe = vm.envAddress("ADMIN");
        wire(address(router));
        vm.stopBroadcast();
    }
}
