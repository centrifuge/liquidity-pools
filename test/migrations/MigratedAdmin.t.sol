// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import {
    MigratedDelayedAdmin, MigratedPauseAdmin, DelayedAdmin, PauseAdmin
} from "./migrationContracts/MigratedAdmin.sol";
import {InvestRedeemFlow} from "./InvestRedeemFlow.t.sol";

contract MigratedAdmin is InvestRedeemFlow {
    function setUp() public override {
        super.setUp();
    }

    function testDelayedAdminMigration() public {
        // Simulate intended upgrade flow
        centrifugeChain.incomingScheduleUpgrade(address(this));
        vm.warp(block.timestamp + 3 days);
        root.executeScheduledRely(address(this));

        // Deploy new PauseAdmin
        MigratedPauseAdmin newPauseAdmin = new MigratedPauseAdmin(address(root));

        // Deploy new DelayedAdmin
        MigratedDelayedAdmin newDelayedAdmin = new MigratedDelayedAdmin(address(root), address(newPauseAdmin));

        // Rewire contracts
        root.rely(address(newDelayedAdmin));
        root.rely(address(newPauseAdmin));
        newPauseAdmin.rely(address(newDelayedAdmin));
        root.deny(address(delayedAdmin));
        root.deny(address(pauseAdmin));

        // clean up
        newPauseAdmin.deny(address(this));
        newDelayedAdmin.deny(address(this));
        root.deny(address(this));

        // verify permissions
        verifyMigratedAdminPermissions(delayedAdmin, newDelayedAdmin, pauseAdmin, newPauseAdmin);

        // TODO: test admin functionality still works
    }

    function verifyMigratedAdminPermissions(
        DelayedAdmin oldDelayedAdmin,
        DelayedAdmin newDelayedAdmin,
        PauseAdmin oldPauseAdmin,
        PauseAdmin newPauseAdmin
    ) public {
        // verify permissions
        assertTrue(address(oldDelayedAdmin) != address(newDelayedAdmin));
        assertTrue(address(oldPauseAdmin) != address(newPauseAdmin));
        assertEq(root.wards(address(newDelayedAdmin)), 1);
        assertEq(root.wards(address(oldDelayedAdmin)), 0);
        assertEq(root.wards(address(newPauseAdmin)), 1);
        assertEq(root.wards(address(oldPauseAdmin)), 0);
        assertEq(newPauseAdmin.wards(address(newDelayedAdmin)), 1);
        assertEq(newPauseAdmin.wards(address(oldDelayedAdmin)), 0);

        // verify dependencies
        assertEq(address(newDelayedAdmin.pauseAdmin()), address(newPauseAdmin));
    }
}
