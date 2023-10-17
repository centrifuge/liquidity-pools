// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import {MigratedLiquidityPool, LiquidityPool} from "./migrationContracts/MigratedLiquidityPool.sol";
import {MigratedPoolManager, PoolManager} from "./migrationContracts/MigratedPoolManager.sol";
import {LiquidityPoolFactory, TrancheTokenFactory} from "src/util/Factory.sol";
import {InvestRedeemFlow} from "./InvestRedeemFlow.t.sol";

interface TrancheTokenLike {
    function rely(address usr) external;
    function deny(address usr) external;
    function restrictionManager() external view returns (address);
    function addTrustedForwarder(address forwarder) external;
    function removeTrustedForwarder(address forwarder) external;
    function trustedForwarders(address) external view returns (bool);
    function wards(address) external view returns (uint256);
    function allowance(address, address) external view returns (uint256);
}

interface AuthLike {
    function rely(address) external;
    function deny(address) external;
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

        // deploy new liquidityPoolFactory
        LiquidityPoolFactory newLiquidityPoolFactory = new LiquidityPoolFactory(address(root));

        // rewire factory contracts
        newLiquidityPoolFactory.rely(address(root));

        // Deploy new liquidity pool
        MigratedLiquidityPool newLiquidityPool = new MigratedLiquidityPool(
            poolId, trancheId, address(erc20), address(LiquidityPool(_lPool).share()), address(escrow), address(investmentManager)
        );

        // set MigratedPoolManager input parameters
        uint64[] memory poolIds = new uint64[](1);
        poolIds[0] = poolId;
        bytes16[][] memory trancheIds = new bytes16[][](1);
        trancheIds[0] = new bytes16[](1);
        trancheIds[0][0] = trancheId;
        address[][] memory allowedCurrencies = new address[][](1);
        allowedCurrencies[0] = new address[](1);
        allowedCurrencies[0][0] = address(erc20);
        address[][][] memory liquidityPoolCurrencies = new address[][][](1);
        liquidityPoolCurrencies[0] = new address[][](1);
        liquidityPoolCurrencies[0][0] = new address[](1);
        liquidityPoolCurrencies[0][0][0] = address(erc20);
        address[][][] memory liquidityPoolOverrides = new address[][][](1);
        liquidityPoolOverrides[0] = new address[][](1);
        liquidityPoolOverrides[0][0] = new address[](1);
        liquidityPoolOverrides[0][0][0] = address(newLiquidityPool);

        // Deploy new MigratedPoolManager
        MigratedPoolManager newPoolManager = new MigratedPoolManager(
            address(escrow),
            address(newLiquidityPoolFactory),
            restrictionManagerFactory,
            trancheTokenFactory,
            address(poolManager),
            poolIds,
            trancheIds,
            allowedCurrencies,
            liquidityPoolCurrencies,
            liquidityPoolOverrides
        );

        // rewire migrated pool manager
        newLiquidityPoolFactory.rely(address(newPoolManager));
        LiquidityPoolFactory(liquidityPoolFactory).rely(address(newPoolManager));
        TrancheTokenFactory(trancheTokenFactory).rely(address(newPoolManager));
        root.relyContract(address(gateway), address(this));
        gateway.file("poolManager", address(newPoolManager));
        root.relyContract(address(investmentManager), address(this));
        investmentManager.file("poolManager", address(newPoolManager));
        newPoolManager.file("investmentManager", address(investmentManager));
        newPoolManager.file("gateway", address(gateway));
        investmentManager.rely(address(newPoolManager));
        investmentManager.deny(address(poolManager));
        newPoolManager.rely(address(root));
        root.relyContract(address(escrow), address(this));
        escrow.rely(address(newPoolManager));
        escrow.deny(address(poolManager));
        root.relyContract(restrictionManagerFactory, address(this));
        AuthLike(restrictionManagerFactory).rely(address(newPoolManager));
        AuthLike(restrictionManagerFactory).deny(address(poolManager));

        // clean up migrated pool manager
        newPoolManager.deny(address(this));
        root.denyContract(address(gateway), address(this));
        root.denyContract(restrictionManagerFactory, address(this));

        // Rewire new liquidity pool
        TrancheTokenLike token = TrancheTokenLike(address(LiquidityPool(_lPool).share()));
        root.relyContract(address(token), address(this));
        token.rely(address(newLiquidityPool));
        token.deny(_lPool);
        token.addTrustedForwarder(address(newLiquidityPool));
        token.removeTrustedForwarder(_lPool);
        investmentManager.rely(address(newLiquidityPool));
        investmentManager.deny(_lPool);
        newLiquidityPool.rely(address(root));
        newLiquidityPool.rely(address(investmentManager));
        // escrow.approve(address(token), address(investmentManager), type(uint256).max);
        escrow.approve(address(token), address(newLiquidityPool), type(uint256).max);
        escrow.approve(address(token), _lPool, 0);

        // clean up new liquidity pool
        newLiquidityPool.deny(address(this));
        root.denyContract(address(token), address(this));
        root.denyContract(address(investmentManager), address(this));
        root.denyContract(address(escrow), address(this));
        root.deny(address(this));

        // verify permissions
        verifyLiquidityPoolPermissions(LiquidityPool(_lPool), newLiquidityPool);

        // TODO: test that everything is working
        _lPool = address(newLiquidityPool);
        poolManager = newPoolManager;
        verifyInvestAndRedeemFlow(poolId, trancheId, _lPool);
    }

    // --- Permissions & Dependencies Checks ---

    function verifyLiquidityPoolPermissions(LiquidityPool oldLiquidityPool, LiquidityPool newLiquidityPool) public {
        // verify permissions
        assertTrue(address(oldLiquidityPool) != address(newLiquidityPool));
        address token = poolManager.getTrancheToken(poolId, trancheId);
        assertEq(TrancheTokenLike(token).wards(address(oldLiquidityPool)), 0);
        assertEq(TrancheTokenLike(token).wards(address(newLiquidityPool)), 1);
        assertEq(TrancheTokenLike(token).trustedForwarders(address(oldLiquidityPool)), false);
        assertEq(TrancheTokenLike(token).trustedForwarders(address(newLiquidityPool)), true);
        assertEq(investmentManager.wards(address(newLiquidityPool)), 1);
        assertEq(investmentManager.wards(address(oldLiquidityPool)), 0);
        assertEq(newLiquidityPool.wards(address(root)), 1);
        assertEq(newLiquidityPool.wards(address(investmentManager)), 1);
        assertEq(TrancheTokenLike(token).allowance(address(escrow), address(oldLiquidityPool)), 0);
        assertEq(TrancheTokenLike(token).allowance(address(escrow), address(newLiquidityPool)), type(uint256).max);

        // verify dependancies
        assertEq(oldLiquidityPool.poolId(), newLiquidityPool.poolId());
        assertEq(oldLiquidityPool.trancheId(), newLiquidityPool.trancheId());
        assertEq(address(oldLiquidityPool.asset()), address(newLiquidityPool.asset()));
        assertEq(address(oldLiquidityPool.share()), address(newLiquidityPool.share()));
        assertEq(address(newLiquidityPool.share()), token);
        assertEq(address(oldLiquidityPool.manager()), address(newLiquidityPool.manager()));
    }
}
