// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import {MigratedRestrictionManager, RestrictionManager} from "./migrationContracts/MigratedRestrictionManager.sol";
// import {TrancheTokenLike} from "src/token/Tranche.sol";
import {LiquidityPool} from "src/LiquidityPool.sol";
import {InvestRedeemFlow} from "./InvestRedeemFlow.t.sol";

contract MigratedRestrictionManagerTest is InvestRedeemFlow {
    function setUp() public override {
        super.setUp();
    }

    function testRestrictionManagerMigration() public {
        // Simulate intended upgrade flow
        centrifugeChain.incomingScheduleUpgrade(address(this));
        vm.warp(block.timestamp + 3 days);
        root.executeScheduledRely(address(this));

        address[] memory restrictionManagerWards = new address[](1);
        restrictionManagerWards[0] = address(poolManager);

        // Deploy new Gateway
        MigratedRestrictionManager newRestrictionManager =
            new MigratedRestrictionManager(address(LiquidityPool(_lPool).share()));

        RestrictionManager oldRestrictionManager =
            RestrictionManager(LiquidityPool(_lPool).share().restrictionManager());

        // Rewire contracts
        root.relyContract(address(LiquidityPool(_lPool).share()), address(this));
        LiquidityPool(_lPool).share().file("restrictionManager", address(newRestrictionManager));
        newRestrictionManager.updateMember(address(escrow), type(uint256).max);
        newRestrictionManager.rely(address(root));
        for (uint256 i = 0; i < restrictionManagerWards.length; i++) {
            newRestrictionManager.rely(restrictionManagerWards[i]);
        }

        // clean up
        newRestrictionManager.deny(address(this));
        root.denyContract(address(LiquidityPool(_lPool).share()), address(this));
        root.deny(address(this));

        // verify permissions
        verifyMigratedRestrictionManagerPermissions(oldRestrictionManager, newRestrictionManager);

        // TODO: test that everything is working
        // restrictionManager = newRestrictionManager;
        // VerifyInvestAndRedeemFlow(poolId, trancheId, _lPool);
    }

    function verifyMigratedRestrictionManagerPermissions(
        RestrictionManager oldRestrictionManager,
        RestrictionManager newRestrictionManager
    ) internal {
        assertTrue(address(oldRestrictionManager) != address(newRestrictionManager));
        assertTrue(oldRestrictionManager.token() == newRestrictionManager.token());
        assertTrue(oldRestrictionManager.hasMember(address(escrow)) == newRestrictionManager.hasMember(address(escrow)));
        assertTrue(newRestrictionManager.wards(address(root)) == 1);
        assertTrue(newRestrictionManager.wards(address(poolManager)) == 1);
    }
}
