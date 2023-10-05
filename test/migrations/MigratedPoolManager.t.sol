// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import {MigratedPoolManager, PoolManager} from "./migrationContracts/MigratedPoolManager.sol";
import {LiquidityPoolFactory, TrancheTokenFactory} from "src/util/Factory.sol";
import {InvestRedeemFlow} from "./InvestRedeemFlow.t.sol";

interface AuthLike {
    function rely(address) external;
    function deny(address) external;
}

contract MigrationsTest is InvestRedeemFlow {
    function setUp() public override {
        super.setUp();
    }

    function testPoolManagerMigrationInvestRedeem() public {
        // Simulate intended upgrade flow
        centrifugeChain.incomingScheduleUpgrade(address(this));
        vm.warp(block.timestamp + 3 days);
        root.executeScheduledRely(address(this));

        // Collect all pools, their tranches, allowed currencies and liquidity pool currencies
        // assume these records are available off-chain
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

        // Deploy new MigratedPoolManager
        MigratedPoolManager newPoolManager = new MigratedPoolManager(
            address(escrow),
            liquidityPoolFactory,
            restrictionManagerFactory,
            trancheTokenFactory,
            address(poolManager),
            poolIds,
            trancheIds,
            allowedCurrencies,
            liquidityPoolCurrencies
        );

        verifyMigratedPoolManagerState(
            poolIds, trancheIds, allowedCurrencies, liquidityPoolCurrencies, poolManager, newPoolManager
        );

        // Rewire contracts
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

        // clean up
        newPoolManager.deny(address(this));
        root.denyContract(address(investmentManager), address(this));
        root.denyContract(address(gateway), address(this));
        root.denyContract(address(newPoolManager), address(this));
        root.denyContract(address(escrow), address(this));
        root.denyContract(restrictionManagerFactory, address(this));
        root.deny(address(this));

        verifyMigratedPoolManagerPermissions(poolManager, newPoolManager);

        // test that everything is working
        poolManager = newPoolManager;
        centrifugeChain.addPool(poolId + 1); // add pool
        centrifugeChain.addTranche(poolId + 1, trancheId, "Test Token 2", "TT2", trancheTokenDecimals); // add tranche
        centrifugeChain.allowInvestmentCurrency(poolId + 1, currencyId);
        poolManager.deployTranche(poolId + 1, trancheId);
        address _lPool2 = poolManager.deployLiquidityPool(poolId + 1, trancheId, address(erc20));
        centrifugeChain.updateMember(poolId + 1, trancheId, investor, uint64(block.timestamp + 1000 days));

        VerifyInvestAndRedeemFlow(poolId + 1, trancheId, _lPool2);
    }

    function verifyMigratedPoolManagerPermissions(PoolManager oldPoolManager, PoolManager newPoolManager) public {
        assertTrue(address(oldPoolManager) != address(newPoolManager));
        assertEq(address(oldPoolManager.escrow()), address(newPoolManager.escrow()));
        assertEq(address(oldPoolManager.liquidityPoolFactory()), address(newPoolManager.liquidityPoolFactory()));
        assertEq(
            address(oldPoolManager.restrictionManagerFactory()), address(newPoolManager.restrictionManagerFactory())
        );
        assertEq(address(oldPoolManager.trancheTokenFactory()), address(newPoolManager.trancheTokenFactory()));
        assertEq(address(oldPoolManager.investmentManager()), address(newPoolManager.investmentManager()));
        assertEq(address(oldPoolManager.gateway()), address(newPoolManager.gateway()));
        assertEq(address(gateway.poolManager()), address(newPoolManager));
        assertEq(address(investmentManager.poolManager()), address(newPoolManager));
        assertEq(newPoolManager.wards(address(root)), 1);
        assertEq(investmentManager.wards(address(newPoolManager)), 1);
        assertEq(investmentManager.wards(address(oldPoolManager)), 0);
        assertEq(escrow.wards(address(newPoolManager)), 1);
        assertEq(escrow.wards(address(oldPoolManager)), 0);
        assertEq(investmentManager.wards(address(newPoolManager)), 1);
        assertEq(investmentManager.wards(address(oldPoolManager)), 0);
    }

    // --- State Verification Helpers ---

    function verifyMigratedPoolManagerState(
        uint64[] memory poolIds,
        bytes16[][] memory trancheIds,
        address[][] memory allowedCurrencies,
        address[][][] memory liquidityPoolCurrencies,
        PoolManager poolManager,
        PoolManager newPoolManager
    ) public {
        for (uint256 i = 0; i < poolIds.length; i++) {
            (uint256 newCreatedAt) = newPoolManager.pools(poolIds[i]);
            (uint256 oldCreatedAt) = poolManager.pools(poolIds[i]);
            assertEq(newCreatedAt, oldCreatedAt);
            verifyUndeployedTranches(poolIds[i], trancheIds[i], poolManager, newPoolManager);

            for (uint256 j = 0; j < trancheIds[i].length; j++) {
                verifyTranche(poolIds[i], trancheIds[i][j], poolManager, newPoolManager);
                for (uint256 k = 0; k < liquidityPoolCurrencies[i][j].length; k++) {
                    verifyLiquidityPoolCurrency(
                        poolIds[i], trancheIds[i][j], liquidityPoolCurrencies[i][j][k], poolManager, newPoolManager
                    );
                }
            }

            for (uint256 j = 0; j < allowedCurrencies[i].length; j++) {
                verifyAllowedCurrency(poolIds[i], allowedCurrencies[i][j], poolManager, newPoolManager);
            }
        }
    }

    function verifyTranche(uint64 poolId, bytes16 trancheId, PoolManager poolManager, PoolManager newPoolManager)
        public
    {
        (address newToken) = newPoolManager.getTrancheToken(poolId, trancheId);
        (address oldToken) = poolManager.getTrancheToken(poolId, trancheId);
        assertEq(newToken, oldToken);
    }

    function verifyUndeployedTranches(
        uint64 poolId,
        bytes16[] memory trancheIds,
        PoolManager poolManager,
        PoolManager newPoolManager
    ) public {
        for (uint256 i = 0; i < trancheIds.length; i++) {
            (uint8 oldDecimals, string memory oldTokenName, string memory oldTokenSymbol) =
                poolManager.undeployedTranches(poolId, trancheIds[i]);
            (uint8 newDecimals, string memory newTokenName, string memory newTokenSymbol) =
                newPoolManager.undeployedTranches(poolId, trancheIds[i]);
            assertEq(newDecimals, oldDecimals);
            assertEq(newTokenName, oldTokenName);
            assertEq(newTokenSymbol, oldTokenSymbol);
        }
    }

    function verifyAllowedCurrency(
        uint64 poolId,
        address currencyAddress,
        PoolManager poolManager,
        PoolManager newPoolManager
    ) public {
        bool newAllowed = newPoolManager.isAllowedAsInvestmentCurrency(poolId, currencyAddress);
        bool oldAllowed = poolManager.isAllowedAsInvestmentCurrency(poolId, currencyAddress);
        assertEq(newAllowed, oldAllowed);
    }

    function verifyLiquidityPoolCurrency(
        uint64 poolId,
        bytes16 trancheId,
        address currencyAddresses,
        PoolManager poolManager,
        PoolManager newPoolManager
    ) public {
        address newLiquidityPool = newPoolManager.getLiquidityPool(poolId, trancheId, currencyAddresses);
        address oldLiquidityPool = poolManager.getLiquidityPool(poolId, trancheId, currencyAddresses);
        assertEq(newLiquidityPool, oldLiquidityPool);
    }
}
