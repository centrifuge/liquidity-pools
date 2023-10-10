// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import {MigratedInvestmentManager, InvestmentManager} from "./migrationContracts/MigratedInvestmentManager.sol";
import {LiquidityPool} from "src/LiquidityPool.sol";
import {InvestRedeemFlow} from "./InvestRedeemFlow.t.sol";

interface AuthLike {
    function rely(address) external;
    function deny(address) external;
}

contract MigratedInvestmentManagerTest is InvestRedeemFlow {
    function setUp() public override {
        super.setUp();
    }

    function testInvestmentManagerMigration() public {
        // Simulate intended upgrade flow
        centrifugeChain.incomingScheduleUpgrade(address(this));
        vm.warp(block.timestamp + 3 days);
        root.executeScheduledRely(address(this));

        // Collect all investors and liquidityPools
        // Assume these records are available off-chain
        address[] memory investors = new address[](1);
        investors[0] = investor;
        address[] memory liquidityPools = new address[](1);
        liquidityPools[0] = _lPool;

        // Deploy new MigratedInvestmentManager
        MigratedInvestmentManager newInvestmentManager =
        new MigratedInvestmentManager(address(escrow), address(userEscrow), address(investmentManager), investors, liquidityPools);

        verifyMigratedInvestmentManagerState(investors, liquidityPools, investmentManager, newInvestmentManager);

        // Rewire contracts
        root.relyContract(address(gateway), address(this));
        gateway.file("investmentManager", address(newInvestmentManager));
        newInvestmentManager.file("poolManager", address(poolManager));
        root.relyContract(address(poolManager), address(this));
        poolManager.file("investmentManager", address(newInvestmentManager));
        newInvestmentManager.file("gateway", address(gateway));
        newInvestmentManager.rely(address(root));
        newInvestmentManager.rely(address(poolManager));
        root.relyContract(address(escrow), address(this));
        escrow.rely(address(newInvestmentManager));
        escrow.deny(address(investmentManager));
        root.relyContract(address(userEscrow), address(this));
        userEscrow.rely(address(newInvestmentManager));
        userEscrow.deny(address(investmentManager));

        // file investmentManager on all LiquidityPools
        for (uint256 i = 0; i < liquidityPools.length; i++) {
            root.relyContract(address(liquidityPools[i]), address(this));
            LiquidityPool lPool = LiquidityPool(liquidityPools[i]);

            lPool.file("manager", address(newInvestmentManager));
            lPool.rely(address(newInvestmentManager));
            lPool.deny(address(investmentManager));
            root.relyContract(address(lPool.share()), address(this));
            AuthLike(address(lPool.share())).rely(address(newInvestmentManager));
            AuthLike(address(lPool.share())).deny(address(investmentManager));
            newInvestmentManager.rely(address(lPool));
            escrow.approve(address(lPool), address(newInvestmentManager), type(uint256).max);
            escrow.approve(address(lPool), address(investmentManager), 0);
        }

        // clean up
        newInvestmentManager.deny(address(this));
        root.denyContract(address(newInvestmentManager), address(this));
        root.denyContract(address(gateway), address(this));
        root.denyContract(address(poolManager), address(this));
        root.denyContract(address(escrow), address(this));
        root.denyContract(address(userEscrow), address(this));
        root.deny(address(this));

        verifyMigratedInvestmentManagerPermissions(investmentManager, newInvestmentManager);

        investmentManager = newInvestmentManager;
        VerifyInvestAndRedeemFlow(poolId, trancheId, _lPool);
    }

    function verifyMigratedInvestmentManagerPermissions(
        InvestmentManager oldInvestmentManager,
        InvestmentManager newInvestmentManager
    ) public {
        assertTrue(address(oldInvestmentManager) != address(newInvestmentManager));
        assertEq(address(oldInvestmentManager.gateway()), address(newInvestmentManager.gateway()));
        assertEq(address(oldInvestmentManager.poolManager()), address(newInvestmentManager.poolManager()));
        assertEq(address(oldInvestmentManager.escrow()), address(newInvestmentManager.escrow()));
        assertEq(address(oldInvestmentManager.userEscrow()), address(newInvestmentManager.userEscrow()));
        assertEq(address(gateway.investmentManager()), address(newInvestmentManager));
        assertEq(address(poolManager.investmentManager()), address(newInvestmentManager));
        assertEq(newInvestmentManager.wards(address(root)), 1);
        assertEq(newInvestmentManager.wards(address(poolManager)), 1);
        assertEq(escrow.wards(address(newInvestmentManager)), 1);
        assertEq(escrow.wards(address(oldInvestmentManager)), 0);
        assertEq(userEscrow.wards(address(newInvestmentManager)), 1);
        assertEq(userEscrow.wards(address(oldInvestmentManager)), 0);
    }

    // --- State Verification Helpers ---

    function verifyMigratedInvestmentManagerState(
        address[] memory investors,
        address[] memory liquidityPools,
        InvestmentManager investmentManager,
        InvestmentManager newInvestmentManager
    ) public {
        for (uint256 i = 0; i < investors.length; i++) {
            for (uint256 j = 0; j < liquidityPools.length; j++) {
                verifyMintDepositWithdraw(investors[i], liquidityPools[j], investmentManager, newInvestmentManager);
                verifyRedeemAndRemainingOrders(investors[i], liquidityPools[j], investmentManager, newInvestmentManager);
            }
        }
    }

    function verifyMintDepositWithdraw(
        address investor,
        address liquidityPool,
        InvestmentManager investmentManager,
        InvestmentManager newInvestmentManager
    ) public {
        (uint128 newMaxMint, uint256 newDepositPrice, uint128 newMaxWithdraw,,,,) =
            newInvestmentManager.investments(investor, liquidityPool);
        (uint128 oldMaxMint, uint256 oldDepositPrice, uint128 oldMaxWithdraw,,,,) =
            investmentManager.investments(investor, liquidityPool);
        assertEq(newMaxMint, oldMaxMint);
        assertEq(newDepositPrice, oldDepositPrice);
        assertEq(newMaxWithdraw, oldMaxWithdraw);
    }

    function verifyRedeemAndRemainingOrders(
        address investor,
        address liquidityPool,
        InvestmentManager investmentManager,
        InvestmentManager newInvestmentManager
    ) public {
        (,,, uint256 newRedeemPrice, uint128 newRemainingDepositRequest, uint128 newRemainingRedeemRequest, bool newExists) =
            newInvestmentManager.investments(investor, liquidityPool);
        (,,, uint256 oldRedeemPrice, uint128 oldRemainingDepositRequest, uint128 oldRemainingRedeemRequest, bool oldExists) =
            investmentManager.investments(investor, liquidityPool);
        assertEq(newRedeemPrice, oldRedeemPrice);
        assertEq(newRemainingDepositRequest, oldRemainingDepositRequest);
        assertEq(newRemainingRedeemRequest, oldRemainingRedeemRequest);
        assertEq(newExists, oldExists);
    }
}
