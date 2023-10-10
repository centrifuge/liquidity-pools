// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import {MigratedGateway, Gateway} from "./migrationContracts/MigratedGateway.sol";
import {InvestRedeemFlow} from "./InvestRedeemFlow.t.sol";

contract MigratedGatewayTest is InvestRedeemFlow {
    function setUp() public override {
        super.setUp();
    }

    function testGatewayMigration() public {
        // Simulate intended upgrade flow
        centrifugeChain.incomingScheduleUpgrade(address(this));
        vm.warp(block.timestamp + 3 days);
        root.executeScheduledRely(address(this));

        // Deploy new Gateway
        MigratedGateway newGateway =
            new MigratedGateway(address(root), address(investmentManager), address(poolManager), address(router));

        // Rewire contracts
        newGateway.rely(address(root));
        root.relyContract(address(investmentManager), address(this));
        investmentManager.file("gateway", address(newGateway));
        root.relyContract(address(poolManager), address(this));
        poolManager.file("gateway", address(newGateway));
        root.relyContract(address(router), address(this));
        router.file("gateway", address(newGateway));

        // clean up
        newGateway.deny(address(this));
        root.denyContract(address(investmentManager), address(this));
        root.denyContract(address(poolManager), address(this));
        root.denyContract(address(router), address(this));
        root.deny(address(this));

        // verify permissions
        verifyMigratedGatewayPermissions(gateway, newGateway);

        // test that everything is working
        gateway = newGateway;
        verifyInvestAndRedeemFlow(poolId, trancheId, _lPool);
    }

    function verifyMigratedGatewayPermissions(Gateway oldGateway, Gateway newGateway) public {
        assertTrue(address(oldGateway) != address(newGateway));
        assertEq(address(oldGateway.investmentManager()), address(newGateway.investmentManager()));
        assertEq(address(oldGateway.poolManager()), address(newGateway.poolManager()));
        assertEq(address(oldGateway.root()), address(newGateway.root()));
        assertEq(address(investmentManager.gateway()), address(newGateway));
        assertEq(address(poolManager.gateway()), address(newGateway));
        assertEq(address(router.gateway()), address(newGateway));
        assertEq(newGateway.wards(address(root)), 1);
    }
}
