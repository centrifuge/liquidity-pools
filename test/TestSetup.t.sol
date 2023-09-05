pragma solidity 0.8.21;
// SPDX-License-Identifier: AGPL-3.0-only
pragma abicoder v2;

// core contracts
import {Root} from "../src/Root.sol";
import {InvestmentManager} from "../src/InvestmentManager.sol";
import {PoolManager, Tranche} from "../src/PoolManager.sol";
import {Escrow} from "../src/Escrow.sol";
import {UserEscrow} from "../src/UserEscrow.sol";
import {LiquidityPoolFactory, TrancheTokenFactory} from "../src/util/Factory.sol";
import {LiquidityPool} from "../src/LiquidityPool.sol";
import {TrancheToken} from "../src/token/Tranche.sol";
import {ERC20} from "../src/token/ERC20.sol";
import {Gateway} from "../src/gateway/Gateway.sol";
import {MemberlistLike, Memberlist} from "../src/token/Memberlist.sol";
import {Messages} from "../src/gateway/Messages.sol";
import {Deployer} from "../script/Deployer.sol";
import "../src/interfaces/IERC20.sol";

// mocks
import {MockHomeLiquidityPools} from "./mock/MockHomeLiquidityPools.sol";
import {MockXcmRouter} from "./mock/MockXcmRouter.sol";

// test env
import "forge-std/Test.sol";
import {Investor} from "./accounts/Investor.sol";

contract TestSetup is Deployer, Test {
    MockHomeLiquidityPools homePools;
    MockXcmRouter mockXcmRouter;
    ERC20 erc20;

    address self;

    uint128 constant MAX_UINT128 = type(uint128).max;

    function setUp() public virtual {
        self = address(this);
        vm.chainId(1);
        // make yourself admin
        admin = self;

        // deploy core contracts
        deployInvestmentManager();
        // deploy mockRouter
        mockXcmRouter = new MockXcmRouter(address(investmentManager));
        // wire contracts
        wire(address(mockXcmRouter));
        // give admin access
        giveAdminAccess();
        // remove deployer access
        // removeDeployerAccess(address(mockXcmRouter)); // need auth permissions in tests

        homePools = new MockHomeLiquidityPools(address(mockXcmRouter));
        erc20 = newErc20("X's Dollar", "USDX", 6);
        mockXcmRouter.file("gateway", address(gateway));
    }

    // helpers
    function newErc20(string memory name, string memory symbol, uint8 decimals) internal returns (ERC20) {
        ERC20 currency = new ERC20(decimals);
        currency.file("name", name);
        currency.file("symbol", symbol);
        return currency;
    }

    function deployLiquidityPool(
        uint64 poolId,
        uint8 trancheTokenDecimals,
        string memory tokenName,
        string memory tokenSymbol,
        bytes16 trancheId,
        uint128 currencyId,
        address currency
    ) public returns (address) {
        homePools.addPool(poolId); // add pool
        homePools.addTranche(poolId, trancheId, tokenName, tokenSymbol, trancheTokenDecimals); // add tranche

        homePools.addCurrency(currencyId, currency);
        homePools.allowPoolCurrency(poolId, currencyId);
        poolManager.deployTranche(poolId, trancheId);

        address lPoolAddress = poolManager.deployLiquidityPool(poolId, trancheId, currency);
        return lPoolAddress;
    }

    function deployLiquidityPool(
        uint64 poolId,
        uint8 decimals,
        string memory tokenName,
        string memory tokenSymbol,
        bytes16 trancheId,
        uint128 currency
    ) public returns (address) {
        deployLiquidityPool(poolId, decimals, tokenName, tokenSymbol, trancheId, currency, address(erc20));
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
}
