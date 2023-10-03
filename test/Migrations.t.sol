// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import "./TestSetup.t.sol";
import {LiquidityPool} from "src/LiquidityPool.sol";
import {MigratedInvestmentManager} from "test/migrationContracts/MigratedInvestmentManager.sol";
import {MigratedPoolManager} from "test/migrationContracts/MigratedPoolManager.sol";
import {MathLib} from "src/util/MathLib.sol";

interface AuthLike {
    function rely(address) external;

    function deny(address) external;
}

contract MigrationsTest is TestSetup {
    using MathLib for uint128;

    uint8 internal constant PRICE_DECIMALS = 18;

    uint64 poolId;
    bytes16 trancheId;
    uint128 currencyId;
    uint8 trancheTokenDecimals;
    address _lPool;
    uint256 investorCurrencyAmount;

    function setUp() public override {
        super.setUp();
        poolId = 1;
        trancheId = bytes16(hex"811acd5b3f17c06841c7e41e9e04cb1b");
        currencyId = 1;
        trancheTokenDecimals = 18;
        _lPool = deployLiquidityPool(
            poolId, trancheTokenDecimals, erc20.name(), erc20.symbol(), trancheId, currencyId, address(erc20)
        );

        investorCurrencyAmount = 1000 * 10 ** erc20.decimals();
        deal(address(erc20), investor, investorCurrencyAmount);
        centrifugeChain.updateMember(poolId, trancheId, investor, uint64(block.timestamp + 1000 days));
        removeDeployerAccess(address(router), address(this));
    }

    // --- Migration Tests ---

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
        root.relyContract(address(userEscrow), address(this));
        userEscrow.rely(address(newInvestmentManager));

        // file investmentManager on all LiquidityPools
        for (uint256 i = 0; i < liquidityPools.length; i++) {
            root.relyContract(address(liquidityPools[i]), address(this));
            LiquidityPool lPool = LiquidityPool(liquidityPools[i]);

            lPool.file("investmentManager", address(newInvestmentManager));
            lPool.rely(address(newInvestmentManager));
            root.relyContract(address(lPool.share()), address(this));
            AuthLike(address(lPool.share())).rely(address(newInvestmentManager));
            newInvestmentManager.rely(address(lPool));
            escrow.approve(address(lPool), address(newInvestmentManager), type(uint256).max);
        }

        // clean up
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

    function testPoolManagerMigrationInvestRedeem() public {
        VerifyInvestAndRedeemFlow(poolId, trancheId, _lPool);

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
        newPoolManager.rely(address(root));
        root.relyContract(address(escrow), address(this));
        escrow.rely(address(newPoolManager));
        root.relyContract(restrictionManagerFactory, address(this));
        AuthLike(restrictionManagerFactory).rely(address(newPoolManager));

        // clean up
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

    // --- Permissions & Dependencies Checks ---

    function verifyMigratedInvestmentManagerPermissions(InvestmentManager oldInvestmentManager, InvestmentManager newInvestmentManager) public {
        assertTrue(address(oldInvestmentManager) != address(newInvestmentManager));
        assertEq(address(oldInvestmentManager.gateway()), address(newInvestmentManager.gateway()));
        assertEq(address(oldInvestmentManager.poolManager()), address(newInvestmentManager.poolManager()));
        assertEq(address(oldInvestmentManager.escrow()), address(newInvestmentManager.escrow()));
        assertEq(address(oldInvestmentManager.userEscrow()), address(newInvestmentManager.userEscrow()));
        assertEq(address(gateway.investmentManager()), address(newInvestmentManager));
        assertEq(address(poolManager.investmentManager()), address(newInvestmentManager));
        assertEq(newInvestmentManager.wards(address(root)), 1);
        assertEq(newInvestmentManager.wards(address(poolManager)), 1);
        assertEq(escrow.wards(address(investmentManager)), 1);
        assertEq(userEscrow.wards(address(investmentManager)), 1);
    }

    function verifyMigratedPoolManagerPermissions(PoolManager oldPoolManager, PoolManager newPoolManager) public {
        assertTrue(address(oldPoolManager) != address(newPoolManager));
        assertEq(address(oldPoolManager.escrow()), address(newPoolManager.escrow()));
        assertEq(address(oldPoolManager.liquidityPoolFactory()), address(newPoolManager.liquidityPoolFactory()));
        assertEq(address(oldPoolManager.restrictionManagerFactory()), address(newPoolManager.restrictionManagerFactory()));
        assertEq(address(oldPoolManager.trancheTokenFactory()), address(newPoolManager.trancheTokenFactory()));
        assertEq(address(oldPoolManager.investmentManager()), address(newPoolManager.investmentManager()));
        assertEq(address(oldPoolManager.gateway()), address(newPoolManager.gateway()));
        assertEq(address(gateway.poolManager()), address(newPoolManager));
        assertEq(address(investmentManager.poolManager()), address(newPoolManager));
        assertEq(investmentManager.wards(address(poolManager)), 1);
        assertEq(poolManager.wards(address(root)), 1);
        assertEq(escrow.wards(address(poolManager)), 1);
        assertEq(investmentManager.wards(address(poolManager)), 1);
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
        (uint128 newMaxMint, uint256 newDepositPrice, uint128 newMaxWithdraw,,,) =
            newInvestmentManager.orderbook(investor, liquidityPool);
        (uint128 oldMaxMint, uint256 oldDepositPrice, uint128 oldMaxWithdraw,,,) =
            investmentManager.orderbook(investor, liquidityPool);
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
        (,,, uint256 newRedeemPrice, uint128 newRemainingInvestOrder, uint128 newRemainingRedeemOrder) =
            newInvestmentManager.orderbook(investor, liquidityPool);
        (,,, uint256 oldRedeemPrice, uint128 oldRemainingInvestOrder, uint128 oldRemainingRedeemOrder) =
            investmentManager.orderbook(investor, liquidityPool);
        assertEq(newRedeemPrice, oldRedeemPrice);
        assertEq(newRemainingInvestOrder, oldRemainingInvestOrder);
        assertEq(newRemainingRedeemOrder, oldRemainingRedeemOrder);
    }

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

    // --- Investment and Redeem Flow ---

    function VerifyInvestAndRedeemFlow(uint64 poolId, bytes16 trancheId, address _lPool) public {
        uint128 price = uint128(2 * 10 ** PRICE_DECIMALS); //TODO: fuzz price
        LiquidityPool lPool = LiquidityPool(_lPool);

        depositMint(poolId, trancheId, price, investorCurrencyAmount, lPool);
        uint256 redeemAmount = lPool.balanceOf(investor);

        redeemWithdraw(poolId, trancheId, price, redeemAmount, lPool);
    }

    function depositMint(uint64 poolId, bytes16 trancheId, uint128 price, uint256 amount, LiquidityPool lPool) public {
        vm.prank(investor);
        erc20.approve(address(investmentManager), amount); // add allowance

        vm.prank(investor);
        lPool.requestDeposit(amount);

        // ensure funds are locked in escrow
        assertEq(erc20.balanceOf(address(escrow)), amount);
        assertEq(erc20.balanceOf(investor), investorCurrencyAmount - amount);

        // trigger executed collectInvest
        uint128 _currencyId = poolManager.currencyAddressToId(address(erc20)); // retrieve currencyId

        uint128 trancheTokensPayout = _toUint128(
            uint128(amount).mulDiv(
                10 ** (PRICE_DECIMALS - erc20.decimals() + lPool.decimals()), price, MathLib.Rounding.Down
            )
        );

        // Assume an epoch execution happens on cent chain
        // Assume a bot calls collectInvest for this user on cent chain
        vm.prank(address(gateway));
        investmentManager.handleExecutedCollectInvest(
            poolId, trancheId, investor, _currencyId, uint128(amount), trancheTokensPayout, 0
        );

        assertEq(lPool.maxMint(investor), trancheTokensPayout);
        assertEq(lPool.maxDeposit(investor), amount);
        assertEq(lPool.balanceOf(address(escrow)), trancheTokensPayout);
        assertEq(erc20.balanceOf(investor), investorCurrencyAmount - amount);

        uint256 div = 2;
        vm.prank(investor);
        lPool.deposit(amount / div, investor);

        assertEq(lPool.balanceOf(investor), trancheTokensPayout / div);
        assertEq(lPool.balanceOf(address(escrow)), trancheTokensPayout - trancheTokensPayout / div);
        assertEq(lPool.maxMint(investor), trancheTokensPayout - trancheTokensPayout / div);
        assertEq(lPool.maxDeposit(investor), amount - amount / div); // max deposit

        uint256 maxMint = lPool.maxMint(investor);
        vm.prank(investor);
        lPool.mint(maxMint, investor);

        assertEq(lPool.balanceOf(investor), trancheTokensPayout);
        assertTrue(lPool.balanceOf(address(escrow)) <= 1);
        assertTrue(lPool.maxMint(investor) <= 1);
    }

    function redeemWithdraw(uint64 poolId, bytes16 trancheId, uint128 price, uint256 amount, LiquidityPool lPool)
        public
    {
        vm.prank(investor);
        lPool.requestRedeem(amount);

        // redeem
        uint128 _currencyId = poolManager.currencyAddressToId(address(erc20)); // retrieve currencyId
        uint128 currencyPayout = _toUint128(
            uint128(amount).mulDiv(price, 10 ** (18 - erc20.decimals() + lPool.decimals()), MathLib.Rounding.Down)
        );
        // Assume an epoch execution happens on cent chain
        // Assume a bot calls collectRedeem for this user on cent chain
        vm.prank(address(gateway));
        investmentManager.handleExecutedCollectRedeem(
            poolId, trancheId, investor, _currencyId, currencyPayout, uint128(amount), 0
        );

        assertEq(lPool.maxWithdraw(investor), currencyPayout);
        assertEq(lPool.maxRedeem(investor), amount);
        assertEq(lPool.balanceOf(address(escrow)), 0);

        uint128 div = 2;
        vm.prank(investor);
        lPool.redeem(amount / div, investor, investor);
        assertEq(lPool.balanceOf(investor), 0);
        assertEq(lPool.balanceOf(address(escrow)), 0);
        assertEq(erc20.balanceOf(investor), currencyPayout / div);
        assertEq(lPool.maxWithdraw(investor), currencyPayout / div);
        assertEq(lPool.maxRedeem(investor), amount / div);

        uint256 maxWithdraw = lPool.maxWithdraw(investor);
        vm.prank(investor);
        lPool.withdraw(maxWithdraw, investor, investor);
        assertEq(lPool.balanceOf(investor), 0);
        assertEq(lPool.balanceOf(address(escrow)), 0);
        assertEq(erc20.balanceOf(investor), currencyPayout);
        assertEq(lPool.maxWithdraw(investor), 0);
        assertEq(lPool.maxRedeem(investor), 0);
    }

    // --- Utils ---

    function _toUint128(uint256 _value) internal pure returns (uint128 value) {
        if (_value > type(uint128).max) {
            revert("InvestmentManager/uint128-overflow");
        } else {
            value = uint128(_value);
        }
    }
}
