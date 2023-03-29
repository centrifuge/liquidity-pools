// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.18;

import {ConnectorAxelarRouter} from "src/routers/axelar/Router.sol";
import {ConnectorGateway} from "src/routers/Gateway.sol";
import {CentrifugeConnector} from "src/Connector.sol";
import {ConnectorEscrow} from "src/Escrow.sol";
import {RestrictedTokenFactory, MemberlistFactory} from "src/token/factory.sol";
import "forge-std/Script.sol";

// Script to deploy Connectors with an Axelar router.
contract ConnectorAxelarScript is Script {
    // address(0)[0:20] + heccak("Centrifuge")[21:32]
    bytes32 SALT = 0x000000000000000000000000000000000000000075eb27011b69f002dc094d05;

    function setUp() public {}

    function run() public {
        vm.startBroadcast();

        address tokenFactory_ = address(new RestrictedTokenFactory{ salt: SALT }());
        address memberlistFactory_ = address(new MemberlistFactory{ salt: SALT }());
        CentrifugeConnector connector =
            new CentrifugeConnector{ salt: SALT }(tokenFactory_, memberlistFactory_);
        address escrow_ = address(new ConnectorEscrow{ salt: SALT }());
        connector.file("escrow", escrow_);

        ConnectorAxelarRouter router = new ConnectorAxelarRouter{ salt: SALT }(
                address(connector),
                address(vm.envAddress("AXELAR_GATEWAY"))
        );
        connector.file("router", address(router));
        ConnectorGateway gateway = new ConnectorGateway{ salt: SALT }(address(connector), address(router));
        // TODO: We should be able to make the gateway address immutable on routers once we're deploying deterministically.
        router.file("gateway", address(gateway));
        vm.stopBroadcast();
    }
}
