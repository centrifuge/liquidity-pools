// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.18;

import {AxelarEVMRouter} from "src/routers/axelar/EVMRouter.sol";
import {Gateway} from "src/Gateway.sol";
import {InvestmentManager} from "src/InvestmentManager.sol";
import {Escrow} from "src/Escrow.sol";
import {PauseAdmin} from "src/admin/PauseAdmin.sol";
import {DelayedAdmin} from "src/admin/DelayedAdmin.sol";
import {LiquidityPoolFactory, MemberlistFactory} from "src/liquidityPool/Factory.sol";
import "forge-std/Script.sol";

// Script to deploy Connectors with an Axelar router.
contract AxelarEVMScript is Script {
    // address(0)[0:20] + keccak("Centrifuge")[21:32]
    bytes32 SALT = 0x000000000000000000000000000000000000000075eb27011b69f002dc094d05;

    function setUp() public {}

    function run() public {
        vm.startBroadcast();

        uint256 shortWait = 24 hours;
        uint256 longWait = 48 hours;
        uint256 gracePeriod = 48 hours;
        address liquidityPoolFactory = address(new LiquidityPoolFactory());
        address memberlistFactory_ = address(new MemberlistFactory());
        address escrow_ = address(new Escrow());
        InvestmentManager investmentManager = new InvestmentManager(escrow_, liquidityPoolFactory, memberlistFactory_);

        AxelarEVMRouter router = new AxelarEVMRouter(
                address(investmentManager),
                address(vm.envAddress("AXELAR_GATEWAY"))
        );
        PauseAdmin pauseAdmin = new PauseAdmin();
        DelayedAdmin delayedAdmin = new DelayedAdmin();
        Gateway gateway = new Gateway(address(investmentManager), address(router), shortWait, longWait, gracePeriod);
        investmentManager.file("gateway", address(gateway));
        gateway.rely(address(pauseAdmin));
        gateway.rely(address(delayedAdmin));
        pauseAdmin.file("gateway", address(gateway));
        delayedAdmin.file("gateway", address(gateway));
        router.file("gateway", address(gateway));
        investmentManager.rely(address(gateway));
        router.rely(address(gateway));
        Escrow(address(escrow_)).rely(address(gateway));
        Escrow(address(escrow_)).rely(address(investmentManager));

        // TODO: rely pauseMultisig on pauseAdmin
        pauseAdmin.rely(address(msg.sender));
        pauseAdmin.deny(address(this));

        // TODO: rely delayedMultisig on delayedAdmin
        delayedAdmin.rely(address(msg.sender));
        delayedAdmin.deny(address(this));

        vm.stopBroadcast();
    }
}
