// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import {MigratedLiquidityPool, LiquidityPool} from "./migrationContracts/MigratedLiquidityPool.sol";
import {InvestRedeemFlow} from "./InvestRedeemFlow.t.sol";

interface TrancheTokenLike {
    function rely(address usr) external;
    function deny(address usr) external;
    function restrictionManager() external view returns (address);
    function addTrustedForwarder(address forwarder) external;
    function removeTrustedForwarder(address forwarder) external;
    function trustedForwarders(address) external view returns (bool);
    function wards(address) external view returns (uint256);
}

contract MigrationsTest is InvestRedeemFlow {
    function setUp() public override {
        super.setUp();
    }

    function testLiquidityPoolMigration() public {
        // Simulate intended upgrade flow
        centrifugeChain.incomingScheduleUpgrade(address(this));
        vm.warp(block.timestamp + 3 days);
        root.executeScheduledRely(address(this));

        // Deploy new LiquidityPool
        MigratedLiquidityPool newLiquidityPool = new MigratedLiquidityPool(
            poolId, trancheId, address(erc20), address(LiquidityPool(_lPool).share()), address(investmentManager)
        );

        // Rewire contracts
        TrancheTokenLike token = TrancheTokenLike(poolManager.getTrancheToken(poolId, trancheId));
        root.relyContract(address(token), address(this));
        token.rely(address(newLiquidityPool));
        token.addTrustedForwarder(address(newLiquidityPool));
        newLiquidityPool.rely(address(root));
        newLiquidityPool.rely(address(investmentManager));
        root.relyContract(address(investmentManager), address(this));
        investmentManager.rely(address(newLiquidityPool));
        investmentManager.deny(_lPool);
        root.relyContract(address(escrow), address(this));
        escrow.approve(address(newLiquidityPool), address(investmentManager), type(uint256).max);
        escrow.approve(address(token), address(newLiquidityPool), type(uint256).max);

        // clean up
        escrow.approve(_lPool, address(investmentManager), 0);
        escrow.approve(address(token), _lPool, 0);
        newLiquidityPool.deny(address(this));
        token.deny(_lPool);
        token.removeTrustedForwarder(_lPool);
        root.denyContract(address(token), address(this));
        root.denyContract(address(investmentManager), address(this));
        root.denyContract(address(escrow), address(this));
        root.deny(address(this));

        // verify permissions
        verifyLiquidityPoolPermissions(LiquidityPool(_lPool), newLiquidityPool);

        // TODO: test that everything is working
        // _lPool = address(newLiquidityPool);
        // verifyInvestAndRedeemFlow(poolId, trancheId, address(_lPool));
    }

    // --- Permissions & Dependencies Checks ---

    function verifyLiquidityPoolPermissions(LiquidityPool oldLiquidityPool, LiquidityPool newLiquidityPool) public {
        assertTrue(address(oldLiquidityPool) != address(newLiquidityPool));
        assertEq(oldLiquidityPool.poolId(), newLiquidityPool.poolId());
        assertEq(oldLiquidityPool.trancheId(), newLiquidityPool.trancheId());
        assertEq(address(oldLiquidityPool.asset()), address(newLiquidityPool.asset()));
        assertEq(address(oldLiquidityPool.share()), address(newLiquidityPool.share()));
        address token = poolManager.getTrancheToken(poolId, trancheId);
        assertEq(address(newLiquidityPool.share()), token);
        assertEq(TrancheTokenLike(token).trustedForwarders(address(oldLiquidityPool)), false);
        assertEq(TrancheTokenLike(token).trustedForwarders(address(newLiquidityPool)), true);
        assertEq(TrancheTokenLike(token).wards(address(oldLiquidityPool)), 0);
        assertEq(TrancheTokenLike(token).wards(address(newLiquidityPool)), 1);
        assertEq(address(oldLiquidityPool.manager()), address(newLiquidityPool.manager()));
        assertEq(newLiquidityPool.wards(address(root)), 1);
        assertEq(newLiquidityPool.wards(address(investmentManager)), 1);
        assertEq(investmentManager.wards(address(newLiquidityPool)), 1);
        assertEq(investmentManager.wards(address(oldLiquidityPool)), 0);
    }
}
