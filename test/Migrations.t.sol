// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import "./TestSetup.t.sol";
import "src/LiquidityPool.sol";
import {MigratedInvestmentManager} from "test/migrationContracts/MigratedInvestmentManager.sol";
import {MigratedPoolManager} from "test/migrationContracts/MigratedPoolManager.sol";
import {MathLib} from "src/util/MathLib.sol";

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
    }

    function testInvestmentManagerMigration() public {
        InvestAndRedeem(poolId, trancheId, _lPool);

        // Assume executeScheduledRely() is called on this spell

        // Assume these records are available off-chain
        address[] memory investors = new address[](1);
        investors[0] = investor;
        address[] memory liquidityPools = new address[](1);
        liquidityPools[0] = _lPool;

        // Deploy new investmentManager
        MigratedInvestmentManager newInvestmentManager =
        new MigratedInvestmentManager(address(escrow), address(userEscrow), address(investmentManager), investors, liquidityPools);

        // Deploy new contracts that take InvestmentManager as constructor argument
        Gateway newGateway =
            new Gateway(address(root), address(newInvestmentManager), address(poolManager), address(router));

        // file investmentManager on all LiquidityPools
        for (uint256 i = 0; i < liquidityPools.length; i++) {
            root.relyContract(address(liquidityPools[i]), address(this));
            LiquidityPool lPool = LiquidityPool(liquidityPools[i]);

            lPool.file("investmentManager", address(newInvestmentManager));
            lPool.rely(address(newInvestmentManager));
            newInvestmentManager.rely(address(lPool));
            escrow.approve(address(lPool), address(newInvestmentManager), type(uint256).max);
        }

        // Rewire everything
        newInvestmentManager.file("poolManager", address(poolManager));
        root.relyContract(address(poolManager), address(this));
        poolManager.file("investmentManager", address(newInvestmentManager));
        newInvestmentManager.file("gateway", address(newGateway));
        poolManager.file("gateway", address(newGateway));
        newInvestmentManager.rely(address(root));
        newInvestmentManager.rely(address(poolManager));
        newGateway.rely(address(root));
        root.relyContract(address(escrow), address(this));
        Escrow(address(escrow)).rely(address(newInvestmentManager));
        root.relyContract(address(userEscrow), address(this));
        UserEscrow(address(userEscrow)).rely(address(newInvestmentManager));

        root.relyContract(address(router), address(this));
        router.file("gateway", address(newGateway));

        // clean up
        root.denyContract(address(newInvestmentManager), address(this));
        root.denyContract(address(newGateway), address(this));
        root.denyContract(address(poolManager), address(this));
        root.denyContract(address(escrow), address(this));
        root.denyContract(address(userEscrow), address(this));
        root.deny(address(this));

        // very state was migrated successfully
        verifyMigratedInvestmentManagerState(investors, liquidityPools, investmentManager, newInvestmentManager);

        // For the sake of these helper functions, set global variables to new contracts
        gateway = newGateway;
        investmentManager = newInvestmentManager;

        // test that everything is working
        InvestAndRedeem(poolId, trancheId, _lPool);
    }

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
        (uint128 newMaxDeposit, uint128 newMaxMint, uint128 newMaxWithdraw,,,) =
            newInvestmentManager.orderbook(investor, liquidityPool);
        (uint128 oldMaxDeposit, uint128 oldMaxMint, uint128 oldMaxWithdraw,,,) =
            investmentManager.orderbook(investor, liquidityPool);
        assertEq(newMaxDeposit, oldMaxDeposit);
        assertEq(newMaxMint, oldMaxMint);
        assertEq(newMaxWithdraw, oldMaxWithdraw);
    }

    function verifyRedeemAndRemainingOrders(
        address investor,
        address liquidityPool,
        InvestmentManager investmentManager,
        InvestmentManager newInvestmentManager
    ) public {
        (,,, uint128 newMaxRedeem, uint128 newRemainingInvestOrder, uint128 newRemainingRedeemOrder) =
            newInvestmentManager.orderbook(investor, liquidityPool);
        (,,, uint128 oldMaxRedeem, uint128 oldRemainingInvestOrder, uint128 oldRemainingRedeemOrder) =
            investmentManager.orderbook(investor, liquidityPool);
        assertEq(newMaxRedeem, oldMaxRedeem);
        assertEq(newRemainingInvestOrder, oldRemainingInvestOrder);
        assertEq(newRemainingRedeemOrder, oldRemainingRedeemOrder);
    }

    function testLiquidityPoolMigration() public {
        InvestAndRedeem(poolId, trancheId, _lPool);

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
    }

    function verifyMigratedPoolManagerState(uint64[] memory poolIds, bytes16[][] memory trancheIds, address[][] memory allowedCurrencies, address[][][] memory liquidityPoolCurrencies, PoolManager poolManager, PoolManager newPoolManager) public {
        for (uint256 i = 0; i < poolIds.length; i++) {
            (, uint256 newCreatedAt) = newPoolManager.pools(poolIds[i]);
            (, uint256 oldCreatedAt) = poolManager.pools(poolIds[i]);
            assertEq(newCreatedAt, oldCreatedAt);

            for (uint256 j = 0; j < trancheIds[i].length; j++) {
                verifyTranche(poolIds[i], trancheIds[i][j], poolManager, newPoolManager);
                for (uint256 k = 0; k < liquidityPoolCurrencies[i][j].length; k++) {
                    verifyLiquidityPoolCurrency(poolIds[i], trancheIds[i][j], liquidityPoolCurrencies[i][j][k], poolManager, newPoolManager);
                }
            }

            for (uint256 j = 0; j < allowedCurrencies[i].length; j++) {
                verifyAllowedCurrency(poolIds[i], allowedCurrencies[i][j], poolManager, newPoolManager);
            }

        }
    }

    function verifyTranche(uint64 poolId, bytes16 trancheId, PoolManager poolManager, PoolManager newPoolManager) public {
        (address newToken, uint8 newDecimals, uint256 newCreatedAt, string memory newTokenName, string memory newTokenSymbol) =
            newPoolManager.getTranche(poolId, trancheId);
        (address oldToken, uint8 oldDecimals, uint256 oldCreatedAt, string memory oldTokenName, string memory oldTokenSymbol) =
            poolManager.getTranche(poolId, trancheId);
        assertEq(newToken, oldToken);
        assertEq(newDecimals, oldDecimals);
        assertEq(newCreatedAt, oldCreatedAt);
        assertEq(newTokenName, oldTokenName);
        assertEq(newTokenSymbol, oldTokenSymbol);
    }

    function verifyAllowedCurrency(uint64 poolId, address currencyAddress, PoolManager poolManager, PoolManager newPoolManager) public {
        bool newAllowed = newPoolManager.isAllowedAsPoolCurrency(poolId, currencyAddress);
        bool oldAllowed = poolManager.isAllowedAsPoolCurrency(poolId, currencyAddress);
        assertEq(newAllowed, oldAllowed);
    }

    function verifyLiquidityPoolCurrency(uint64 poolId, bytes16 trancheId, address currencyAddresses, PoolManager poolManager, PoolManager newPoolManager) public {
        address newLiquidityPool = newPoolManager.getLiquidityPool(poolId, trancheId, currencyAddresses);
        address oldLiquidityPool = poolManager.getLiquidityPool(poolId, trancheId, currencyAddresses);
        assertEq(newLiquidityPool, oldLiquidityPool);
    }

    function testRootMigration() public {}

    function testPoolManagerMigration() public {}

    // --- Investment and Redeem Flow ---

    function InvestAndRedeem(uint64 poolId, bytes16 trancheId, address _lPool) public {
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
        lPool.requestDeposit(amount, investor);

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
        vm.expectRevert(bytes("ERC20/insufficient-allowance"));
        vm.prank(investor);
        lPool.requestRedeem(amount, investor);
        vm.prank(investor);
        lPool.approve(address(investmentManager), amount);
        vm.prank(investor);
        lPool.requestRedeem(amount, investor);

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

    // --- Helpers ---

    function _toUint128(uint256 _value) internal pure returns (uint128 value) {
        if (_value > type(uint128).max) {
            revert("InvestmentManager/uint128-overflow");
        } else {
            value = uint128(_value);
        }
    }
}
