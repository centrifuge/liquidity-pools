// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.18;

import {ConnectorXCMRouter} from "src/routers/xcm/Router.sol";
import {CentrifugeConnector} from "src/Connector.sol";
import {ConnectorEscrow} from "src/Escrow.sol";
import {RestrictedTokenFactory, MemberlistFactory} from "src/token/factory.sol";
import "forge-std/Script.sol";

// Script to deploy Connectors with an XCM router.
contract ConnectorXCMScript is Script {
    // address(0)[0:20] + heccak("Centrifuge")[21:32]
    bytes32 SALT = 0x000000000000000000000000000000000000000075eb27011b69f002dc094d05;

    function setUp() public {}

    function run() public {
        vm.startBroadcast();

        address escrow_ = address(new ConnectorEscrow{ salt: SALT }());
        address tokenFactory_ = address(new RestrictedTokenFactory{ salt: SALT }());
        address memberlistFactory_ = address(new MemberlistFactory{ salt: SALT }());
        CentrifugeConnector connector =
            new CentrifugeConnector{ salt: SALT }(escrow_, tokenFactory_, memberlistFactory_);

        ConnectorXCMRouter router = new ConnectorXCMRouter{ salt: SALT }(
                address(connector),
                address(vm.envAddress("CENTRIFUGE_CHAIN_ORIGIN")),
                uint8(vm.envUint("CENTRIFUGE_CHAIN_CONNECTORS_PALLET_INDEX")),
                uint8(vm.envUint("CENTRIFUGE_CHAIN_CONNECTORS_PALLET_HANDLE_INDEX"))
        );
        connector.file("router", address(router));
        vm.stopBroadcast();
    }
}
