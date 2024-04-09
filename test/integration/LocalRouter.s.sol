// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import {Deployer, RouterLike} from "../../script/Deployer.sol";
import {LocalRouter} from "./LocalRouter.sol";

interface LiquidityPoolLike {
    function requestDeposit(uint256 assets, address owner) external;
}

// Script to deploy Liquidity Pools with an Axelar router.
contract LocalRouterScript is Deployer {
    function setUp() public {}

    function run() public {
        // NOTE: 0x361c43cd5Fd700923Aae9dED678851a201839fc6 is the H160 of Keyring::Admin in the Centrifuge Chain
        // repository
        admin = address(0x361c43cd5Fd700923Aae9dED678851a201839fc6);
        pausers = [address(0x361c43cd5Fd700923Aae9dED678851a201839fc6)];

        deploy(msg.sender);
        LocalRouter router = new LocalRouter();
        wire(address(router));
        router.file("gateway", address(gateway));
        router.file("sourceChain", "TestDomain");
        router.file("sourceAddress", "0x1111111111111111111111111111111111111111");

        giveAdminAccess();
        removeDeployerAccess(msg.sender);
    }
}
