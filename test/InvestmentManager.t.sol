// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.18;
pragma abicoder v2;

import {InvestmentManager, Tranche} from "../src/InvestmentManager.sol";
import {TokenManager} from "../src/TokenManager.sol";
import {Gateway} from "../src/Gateway.sol";
import {Escrow} from "../src/Escrow.sol";
import {LiquidityPoolFactory, TrancheTokenFactory, MemberlistFactory} from "../src/liquidityPool/Factory.sol";
import {LiquidityPool} from "../src/liquidityPool/LiquidityPool.sol";
import {RestrictedToken} from "../src/token/Restricted.sol";
import {ERC20} from "../src/token/ERC20.sol";

import {MemberlistLike, Memberlist} from "../src/token/Memberlist.sol";
import {MockHomeLiquidityPools} from "./mock/MockHomeLiquidityPools.sol";
import {MockXcmRouter} from "./mock/MockXcmRouter.sol";
import {Messages} from "../src/Messages.sol";
import {PauseAdmin} from "../src/admin/PauseAdmin.sol";
import {DelayedAdmin} from "../src/admin/DelayedAdmin.sol";
import "forge-std/Test.sol";
import "../src/InvestmentManager.sol";

interface EscrowLike_ {
    function approve(address token, address spender, uint256 value) external;
    function rely(address usr) external;
}

interface AuthLike_ {
    function wards(address user) external returns (uint256);
}

contract InvestmentManagerTest is Test {
    InvestmentManager evmInvestmentManager;
    TokenManager evmTokenManager;
    Gateway gateway;
    MockHomeLiquidityPools homePools;
    MockXcmRouter mockXcmRouter;

    function setUp() public {
        vm.chainId(1);
        uint256 shortWait = 24 hours;
        uint256 longWait = 48 hours;
        uint256 gracePeriod = 48 hours;
        address escrow_ = address(new Escrow());
        address liquidityPoolFactory_ = address(new LiquidityPoolFactory());
        address trancheTokenFactory_ = address(new TrancheTokenFactory());
        address memberlistFactory_ = address(new MemberlistFactory());

        evmInvestmentManager =
            new InvestmentManager(escrow_, liquidityPoolFactory_, trancheTokenFactory_, memberlistFactory_);
        evmTokenManager = new TokenManager(escrow_);

        mockXcmRouter = new MockXcmRouter(address(evmInvestmentManager));

        homePools = new MockHomeLiquidityPools(address(mockXcmRouter));
        PauseAdmin pauseAdmin = new PauseAdmin();
        DelayedAdmin delayedAdmin = new DelayedAdmin();

        gateway =
        new Gateway(address(evmInvestmentManager), address(evmTokenManager), address(mockXcmRouter), shortWait, longWait, gracePeriod);
        gateway.rely(address(pauseAdmin));
        gateway.rely(address(delayedAdmin));
        pauseAdmin.file("gateway", address(gateway));
        delayedAdmin.file("gateway", address(gateway));
        evmInvestmentManager.file("gateway", address(gateway));
        evmInvestmentManager.file("tokenManager", address(evmTokenManager));
        evmTokenManager.file("gateway", address(gateway));
        evmTokenManager.file("investmentManager", address(evmInvestmentManager));
        EscrowLike_(escrow_).rely(address(evmInvestmentManager));
        EscrowLike_(escrow_).rely(address(evmTokenManager));
        mockXcmRouter.file("gateway", address(gateway));
        evmInvestmentManager.rely(address(gateway));
        Escrow(escrow_).rely(address(gateway));
    }

    // function testConnectorDeactivationWorks() public {
    //     gateway.pause();
    //     vm.expectRevert(bytes("InvestmentManager/connector-deactivated"));
    //     evmInvestmentManager.processDeposit(address(0), address(0), 0);
    // }

    function testAddPoolWorks(uint64 poolId) public {
        homePools.addPool(poolId);
        (uint64 actualPoolId,,) = evmInvestmentManager.pools(poolId);
        assertEq(uint256(actualPoolId), uint256(poolId));
    }

    function testAllowPoolCurrencyWorks(uint128 currency, uint64 poolId) public {
        vm.assume(currency > 0);
        ERC20 token = newErc20("X's Dollar", "USDX", 42);
        homePools.addCurrency(currency, address(token));
        homePools.addPool(poolId);

        homePools.allowPoolCurrency(poolId, currency);
        assertTrue(evmInvestmentManager.allowedPoolCurrencies(poolId, address(token)));
    }

    function testAllowPoolCurrencyWithUnknownCurrencyFails(uint128 currency, uint64 poolId) public {
        homePools.addPool(poolId);
        vm.expectRevert(bytes("InvestmentManager/unknown-currency"));
        homePools.allowPoolCurrency(poolId, currency);
    }

    function testAddingPoolMultipleTimesFails(uint64 poolId) public {
        homePools.addPool(poolId);

        vm.expectRevert(bytes("InvestmentManager/pool-already-added"));
        homePools.addPool(poolId);
    }

    function testAddingPoolAsNonRouterFails(uint64 poolId) public {
        vm.expectRevert(bytes("InvestmentManager/not-the-gateway"));
        evmInvestmentManager.addPool(poolId);
    }

    function testAddingSingleTrancheWorks(
        uint64 poolId,
        bytes16 trancheId,
        string memory tokenName,
        string memory tokenSymbol,
        uint8 decimals,
        uint128 price
    ) public {
        homePools.addPool(poolId);
        (uint64 actualPoolId,,) = evmInvestmentManager.pools(poolId);
        assertEq(uint256(actualPoolId), uint256(poolId));
        homePools.addTranche(poolId, trancheId, tokenName, tokenSymbol, decimals, price);
        (
            address token,
            uint64 poolId_,
            bytes16 trancheId_,
            uint8 decimals_,
            uint256 createdAt_,
            string memory tokenName_,
            string memory tokenSymbol_
        ) = evmInvestmentManager.tranches(poolId, trancheId);

        assertEq(poolId, poolId_);
        assertEq(trancheId, trancheId_);
        assertEq(block.timestamp, createdAt_);
        assertEq(bytes32ToString(stringToBytes32(tokenName)), bytes32ToString(stringToBytes32(tokenName_)));
        assertEq(bytes32ToString(stringToBytes32(tokenSymbol)), bytes32ToString(stringToBytes32(tokenSymbol_)));
        assertEq(decimals, decimals_);
    }

    function testAddingTrancheMultipleTimesFails(
        uint64 poolId,
        uint8 decimals,
        string memory tokenName,
        string memory tokenSymbol,
        bytes16 trancheId,
        uint128 price
    ) public {
        homePools.addPool(poolId);
        homePools.addTranche(poolId, trancheId, tokenName, tokenSymbol, decimals, price);

        vm.expectRevert(bytes("InvestmentManager/tranche-already-exists"));
        homePools.addTranche(poolId, trancheId, tokenName, tokenSymbol, decimals, price);
    }

    function testAddingMultipleTranchesWorks(
        uint64 poolId,
        bytes16[] calldata trancheIds,
        string memory tokenName,
        string memory tokenSymbol,
        uint8 decimals,
        uint128 price
    ) public {
        vm.assume(trancheIds.length > 0 && trancheIds.length < 5);
        vm.assume(!hasDuplicates(trancheIds));
        homePools.addPool(poolId);

        for (uint256 i = 0; i < trancheIds.length; i++) {
            homePools.addTranche(poolId, trancheIds[i], tokenName, tokenSymbol, decimals, price);
            (, uint64 poolId_, bytes16 trancheId_,,,,) = evmInvestmentManager.tranches(poolId, trancheIds[i]);

            assertEq(poolId, poolId_);
            assertEq(trancheIds[i], trancheId_);
        }
    }

    function testAddingTranchesAsNonRouterFails(
        uint64 poolId,
        bytes16 trancheId,
        string memory tokenName,
        string memory tokenSymbol,
        uint8 decimals,
        uint128 price
    ) public {
        homePools.addPool(poolId);
        vm.expectRevert(bytes("InvestmentManager/not-the-gateway"));
        evmInvestmentManager.addTranche(poolId, trancheId, tokenName, tokenSymbol, decimals, price);
    }

    function testAddingTranchesForNonExistentPoolFails(
        uint64 poolId,
        bytes16 trancheId,
        string memory tokenName,
        string memory tokenSymbol,
        uint8 decimals,
        uint128 price
    ) public {
        vm.expectRevert(bytes("InvestmentManager/invalid-pool"));
        homePools.addTranche(poolId, trancheId, tokenName, tokenSymbol, decimals, price);
    }

    function testDeployLiquidityPool(
        uint64 poolId,
        uint8 decimals,
        string memory tokenName,
        string memory tokenSymbol,
        bytes16 trancheId,
        uint128 price,
        uint128 currency
    ) public {
        vm.assume(currency > 0);
        ERC20 erc20 = newErc20("X's Dollar", "USDX", 42);
        homePools.addPool(poolId); // add pool
        homePools.addTranche(poolId, trancheId, tokenName, tokenSymbol, decimals, price); // add tranche

        homePools.addCurrency(currency, address(erc20));
        homePools.allowPoolCurrency(poolId, currency);

        address trancheToken_ = evmInvestmentManager.deployTranche(poolId, trancheId);
        address lPoolAddress = evmInvestmentManager.deployLiquidityPool(poolId, trancheId, address(erc20));
        address lPool_ = evmInvestmentManager.liquidityPools(poolId, trancheId, address(erc20)); // make sure the pool was stored in connectors

        // make sure the pool was added to the tranche struct
        assertEq(lPoolAddress, lPool_);

        // check LiquidityPool state
        LiquidityPool lPool = LiquidityPool(lPool_);
        RestrictedToken trancheToken = RestrictedToken(trancheToken_);
        assertEq(address(lPool.investmentManager()), address(evmInvestmentManager));
        assertEq(lPool.asset(), address(erc20));
        assertEq(lPool.poolId(), poolId);
        assertEq(lPool.trancheId(), trancheId);

        assertTrue(lPool.wards(address(gateway)) == 1);
        assertTrue(lPool.wards(address(evmInvestmentManager)) == 1);
        assertTrue(lPool.wards(address(this)) == 0);
        assertTrue(evmInvestmentManager.wards(lPoolAddress) == 1);

        assertEq(trancheToken.name(), bytes32ToString(stringToBytes32(tokenName)));
        assertEq(trancheToken.symbol(), bytes32ToString(stringToBytes32(tokenSymbol)));
        assertEq(trancheToken.decimals(), decimals);
        assertTrue(trancheToken.hasMember(address(evmInvestmentManager.escrow())));

        assertTrue(trancheToken.wards(address(gateway)) == 1);
        assertTrue(trancheToken.wards(address(evmInvestmentManager)) == 1);
        assertTrue(trancheToken.wards(lPool_) == 1);
        assertTrue(trancheToken.wards(address(this)) == 0);
    }

    function testDeployingLiquidityPoolNonExistingTrancheFails(
        uint64 poolId,
        uint8 decimals,
        string memory tokenName,
        string memory tokenSymbol,
        bytes16 trancheId,
        bytes16 wrongTrancheId,
        uint128 price,
        uint128 currency
    ) public {
        vm.assume(currency > 0);
        vm.assume(trancheId != wrongTrancheId);

        ERC20 erc20 = newErc20("X's Dollar", "USDX", 42);
        homePools.addPool(poolId); // add pool
        homePools.addTranche(poolId, trancheId, tokenName, tokenSymbol, decimals, price); // add tranche

        homePools.addCurrency(currency, address(erc20));
        homePools.allowPoolCurrency(poolId, currency);
        vm.expectRevert(bytes("InvestmentManager/tranche-does-not-exist"));
        evmInvestmentManager.deployLiquidityPool(poolId, wrongTrancheId, address(erc20));
    }

    function testDeployingLiquidityPoolNonExistingPoolFails(
        uint64 poolId,
        uint8 decimals,
        string memory tokenName,
        string memory tokenSymbol,
        bytes16 trancheId,
        uint64 wrongPoolId,
        uint128 price,
        uint128 currency
    ) public {
        vm.assume(currency > 0);
        vm.assume(poolId != wrongPoolId);

        ERC20 erc20 = newErc20("X's Dollar", "USDX", 42);
        homePools.addPool(poolId); // add pool
        homePools.addTranche(poolId, trancheId, tokenName, tokenSymbol, decimals, price); // add tranche

        homePools.addCurrency(currency, address(erc20));
        homePools.allowPoolCurrency(poolId, currency);
        vm.expectRevert(bytes("InvestmentManager/pool-does-not-exist"));
        evmInvestmentManager.deployLiquidityPool(wrongPoolId, trancheId, address(erc20));
    }

    function testDeployingLiquidityPoolCurrencyNotSupportedFails(
        uint64 poolId,
        uint8 decimals,
        string memory tokenName,
        string memory tokenSymbol,
        bytes16 trancheId,
        uint128 price,
        uint128 currency
    ) public {
        vm.assume(currency > 0);

        ERC20 erc20 = newErc20("X's Dollar", "USDX", 42);
        homePools.addPool(poolId); // add pool
        homePools.addTranche(poolId, trancheId, tokenName, tokenSymbol, decimals, price); // add tranche
        evmInvestmentManager.deployTranche(poolId, trancheId);

        homePools.addCurrency(currency, address(erc20));

        vm.expectRevert(bytes("InvestmentManager/pool-currency-not-allowed"));
        evmInvestmentManager.deployLiquidityPool(poolId, trancheId, address(erc20));
    }

    function testDeployLiquidityPoolTwiceFails(
        uint64 poolId,
        uint8 decimals,
        string memory tokenName,
        string memory tokenSymbol,
        bytes16 trancheId,
        uint128 price,
        uint128 currency
    ) public {
        vm.assume(currency > 0);
        ERC20 erc20 = newErc20("X's Dollar", "USDX", 42);
        homePools.addPool(poolId); // add pool
        homePools.addTranche(poolId, trancheId, tokenName, tokenSymbol, decimals, price); // add tranche

        homePools.addCurrency(currency, address(erc20));
        homePools.allowPoolCurrency(poolId, currency);
        evmInvestmentManager.deployTranche(poolId, trancheId);

        evmInvestmentManager.deployLiquidityPool(poolId, trancheId, address(erc20));
        vm.expectRevert(bytes("InvestmentManager/liquidityPool-already-deployed"));
        evmInvestmentManager.deployLiquidityPool(poolId, trancheId, address(erc20));
    }

    // helpers
    function deployLiquidityPool(
        uint64 poolId,
        uint8 decimals,
        string memory tokenName,
        string memory tokenSymbol,
        bytes16 trancheId,
        uint128 currency
    ) internal returns (address lPool) {
        // deploy liquidityPool
        ERC20 erc20 = newErc20("X's Dollar", "USDX", 42);
        homePools.addPool(poolId); // add pool
        homePools.addTranche(poolId, trancheId, tokenName, tokenSymbol, decimals, 0); // add tranche
        homePools.addCurrency(currency, address(erc20));
        homePools.allowPoolCurrency(poolId, currency);

        evmInvestmentManager.deployTranche(poolId, trancheId);
        lPool = evmInvestmentManager.deployLiquidityPool(poolId, trancheId, address(erc20));
    }

    function newErc20(string memory name, string memory symbol, uint8 decimals) internal returns (ERC20) {
        ERC20 erc20 = new ERC20(decimals);
        erc20.file("name", name);
        erc20.file("symbol", symbol);

        return erc20;
    }

    function stringToBytes32(string memory source) internal pure returns (bytes32 result) {
        bytes memory tempEmptyStringTest = bytes(source);
        if (tempEmptyStringTest.length == 0) {
            return 0x0;
        }

        assembly {
            result := mload(add(source, 32))
        }
    }

    function bytes32ToString(bytes32 _bytes32) internal pure returns (string memory) {
        uint8 i = 0;
        while (i < 32 && _bytes32[i] != 0) {
            i++;
        }

        bytes memory bytesArray = new bytes(i);
        for (i = 0; i < 32 && _bytes32[i] != 0; i++) {
            bytesArray[i] = _bytes32[i];
        }
        return string(bytesArray);
    }

    function toBytes32(bytes memory f) internal pure returns (bytes16 fc) {
        assembly {
            fc := mload(add(f, 32))
        }
        return fc;
    }

    function toBytes29(bytes memory f) internal pure returns (bytes29 fc) {
        assembly {
            fc := mload(add(f, 29))
        }
        return fc;
    }

    function hasDuplicates(bytes16[] calldata array) internal pure returns (bool) {
        uint256 length = array.length;
        for (uint256 i = 0; i < length; i++) {
            for (uint256 j = i + 1; j < length; j++) {
                if (array[i] == array[j]) {
                    return true;
                }
            }
        }
        return false;
    }
}
