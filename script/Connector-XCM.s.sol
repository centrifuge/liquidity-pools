// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.18;

import {ConnectorXCMRouter} from "src/routers/xcm/Router.sol";
import {ConnectorGateway} from "src/routers/Gateway.sol";
import {CentrifugeConnector} from "src/Connector.sol";
import {ConnectorEscrow} from "src/Escrow.sol";
import {ConnectorPauseAdmin} from "src/admin/PauseAdmin.sol";
import {ConnectorDelayedAdmin} from "src/admin/DelayedAdmin.sol";
import {TrancheTokenFactory, MemberlistFactory} from "src/token/factory.sol";
import "forge-std/Script.sol";

// Script to deploy Connectors with an XCM router.
contract ConnectorXCMScript is Script {
    // address(0)[0:20] + keccak("Centrifuge")[21:32]
    bytes32 SALT = 0x000000000000000000000000000000000000000075eb27011b69f002dc094d05;

    function setUp() public {}

    function run() public {
        vm.startBroadcast();

        uint256 shortWait = 24 hours;
        uint256 longWait = 48 hours;
        uint256 gracePeriod = 48 hours;
        address tokenFactory_ = address(new TrancheTokenFactory{ salt: SALT }());
        address memberlistFactory_ = address(new MemberlistFactory{ salt: SALT }());
        address escrow_ = address(new ConnectorEscrow{ salt: SALT }());
        CentrifugeConnector connector =
            new CentrifugeConnector{ salt: SALT }(escrow_, tokenFactory_, memberlistFactory_);

        ConnectorXCMRouter router = new ConnectorXCMRouter{ salt: SALT }(
                address(vm.envAddress("CENTRIFUGE_CHAIN_ORIGIN")),
                uint8(vm.envUint("CENTRIFUGE_CHAIN_CONNECTORS_PALLET_INDEX")),
                uint8(vm.envUint("CENTRIFUGE_CHAIN_CONNECTORS_PALLET_HANDLE_INDEX"))
        );
        connector.file("router", address(router));
        ConnectorPauseAdmin pauseAdmin = new ConnectorPauseAdmin();
        ConnectorDelayedAdmin delayedAdmin = new ConnectorDelayedAdmin();
        ConnectorGateway gateway =
            new ConnectorGateway{ salt: SALT }(address(connector), address(router), shortWait, longWait, gracePeriod);
        gateway.rely(address(pauseAdmin));
        gateway.rely(address(delayedAdmin));
        pauseAdmin.file("gateway", address(gateway));
        delayedAdmin.file("gateway", address(gateway));
        router.file("gateway", address(gateway));
        connector.rely(address(gateway));
        router.rely(address(gateway));
        ConnectorEscrow(address(escrow_)).rely(address(gateway));

        // rely multisig on pauseAdmin
        pauseAdmin.rely(address(0));
        pauseAdmin.deny(address(this));

        // rely delayedMultisig on delayedAdmin
        delayedAdmin.rely(address(1));
        delayedAdmin.deny(address(this));

        vm.stopBroadcast();
    }
}
