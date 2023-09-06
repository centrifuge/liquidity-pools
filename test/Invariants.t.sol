// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import {TestSetup} from "test/TestSetup.t.sol";
import {InvariantPoolManager} from "test/accounts/PoolManager.sol";
import "forge-std/Test.sol";

contract ConnectorInvariants is TestSetup {
    InvariantPoolManager invariantPoolManager;

    address[] private targetContracts_;

    function setUp() public override {
        super.setUp();

        // Performs random pool and tranches creations
        invariantPoolManager = new InvariantPoolManager(homePools);
        targetContracts_.push(address(poolManager));
    }

    function targetContracts() public returns (address[] memory) {
        return targetContracts_;
    }

    // Invariant 1: For every tranche that exists, the equivalent pool exists
    function invariantTrancheRequiresPool() external {
        for (uint256 i = 0; i < invariantPoolManager.allTranchesLength(); i++) {
            bytes16 trancheId = invariantPoolManager.allTranches(i);
            uint64 poolId = invariantPoolManager.trancheIdToPoolId(trancheId);
            (,, uint256 createdAt) = poolManager.pools(poolId);
            assertTrue(createdAt > 0);
        }
    }
}