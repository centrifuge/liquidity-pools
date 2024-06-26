// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import {Deployer, RouterLike} from "../../script/Deployer.sol";
import {PassthroughRouter} from "./PassthroughRouter.sol";

contract PassthroughRouterScript is Deployer {
    function setUp() public {}

    function run() public {
        vm.startBroadcast();

        admin = vm.envAddress("ADMIN");
        pausers = vm.envAddress("PAUSERS", ",");

        deployInvestmentManager(msg.sender);
        PassthroughRouter router = new PassthroughRouter();
        wire(address(router));
        router.file("gateway", address(gateway));

        giveAdminAccess();
        removeDeployerAccess(address(router), msg.sender);

        vm.stopBroadcast();
    }
}
