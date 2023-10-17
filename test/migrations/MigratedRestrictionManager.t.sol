// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import {MigratedRestrictionManager, RestrictionManager} from "./migrationContracts/MigratedRestrictionManager.sol";
import {RestrictionManagerFactory} from "src/util/Factory.sol";
import {LiquidityPool} from "src/LiquidityPool.sol";
import {InvestRedeemFlow} from "./InvestRedeemFlow.t.sol";

interface TrancheTokenLike {
    function restrictionManager() external view returns (address);
    function file(bytes32, address) external;
}

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
        address token = address(LiquidityPool(_lPool).share());
        RestrictionManager oldRestrictionManager = RestrictionManager(TrancheTokenLike(token).restrictionManager());

        // Deploy new RestrictionManagerFactory
        RestrictionManagerFactory newRestrictionManagerFactory = new RestrictionManagerFactory(address(root));

        // rewire factory contracts
        root.relyContract(address(poolManager), address(this));
        poolManager.file("restrictionManagerFactory", address(newRestrictionManagerFactory));
        newRestrictionManagerFactory.rely(address(poolManager));
        newRestrictionManagerFactory.rely(address(root));

        // Collect all tranche tokens
        // assume these records are available off-chain
        address[] memory trancheTokens = new address[](1);
        trancheTokens[0] = token;

        // Deploy new RestrictionManager for each tranche token
        for (uint256 i = 0; i < trancheTokens.length; i++) {
            MigratedRestrictionManager newRestrictionManager = new MigratedRestrictionManager(token);

            // Rewire contracts
            root.relyContract(trancheTokens[i], address(this));
            TrancheTokenLike(trancheTokens[i]).file("restrictionManager", address(newRestrictionManager));
            newRestrictionManager.updateMember(address(escrow), type(uint256).max);
            newRestrictionManager.rely(address(root));
            for (uint256 j = 0; j < restrictionManagerWards.length; j++) {
                newRestrictionManager.rely(restrictionManagerWards[j]);
            }

            // clean up
            newRestrictionManager.deny(address(this));
            root.denyContract(trancheTokens[i], address(this));
            root.deny(address(this));

            // verify permissions
            verifyMigratedRestrictionManagerPermissions(oldRestrictionManager, newRestrictionManager);
        }

        // TODO: test that everything is working
        // restrictionManager = newRestrictionManager;
        // verifyInvestAndRedeemFlow(poolId, trancheId, _lPool);
    }

    function verifyMigratedRestrictionManagerPermissions(
        RestrictionManager oldRestrictionManager,
        MigratedRestrictionManager newRestrictionManager
    ) internal {
        // verify permissions
        TrancheTokenLike token = TrancheTokenLike(address(oldRestrictionManager.token()));
        assertEq(TrancheTokenLike(token).restrictionManager(), address(newRestrictionManager));
        assertTrue(address(oldRestrictionManager) != address(newRestrictionManager));
        assertTrue(oldRestrictionManager.hasMember(address(escrow)) == newRestrictionManager.hasMember(address(escrow)));
        assertTrue(newRestrictionManager.wards(address(root)) == 1);
        assertTrue(newRestrictionManager.wards(address(poolManager)) == 1);

        // verify dependancies
        assertTrue(oldRestrictionManager.token() == newRestrictionManager.token());
    }
}
