pragma solidity ^0.8.18;
// SPDX-License-Identifier: AGPL-3.0-only
pragma abicoder v2;

// core contracts
import {Root} from "../src/Root.sol";
import {InvestmentManager} from "../src/InvestmentManager.sol";
import {PoolManager, Tranche} from "../src/PoolManager.sol";
import {Escrow} from "../src/Escrow.sol";
import {LiquidityPoolFactory, TrancheTokenFactory} from "../src/util/Factory.sol";
import {LiquidityPool} from "../src/LiquidityPool.sol";
import {TrancheToken} from "../src/token/Tranche.sol";
import {ERC20} from "../src/token/ERC20.sol";
import {Gateway} from "../src/gateway/Gateway.sol";
import {MemberlistLike, Memberlist} from "../src/token/Memberlist.sol";
import {Messages} from "../src/gateway/Messages.sol";
import "../src/token/ERC20Like.sol";

// mocks
import {MockHomeLiquidityPools} from "./mock/MockHomeLiquidityPools.sol";
import {MockXcmRouter} from "./mock/MockXcmRouter.sol";

// test env
import "forge-std/Test.sol";
import {Investor} from "./accounts/Investor.sol";

contract TestSetup is Test {
    Root root;
    InvestmentManager evmInvestmentManager;
    PoolManager evmPoolManager;
    Gateway gateway;
    MockHomeLiquidityPools homePools;
    MockXcmRouter mockXcmRouter;
    Escrow escrow;
    ERC20 erc20;

    address self;

    uint128 constant MAX_UINT128 = type(uint128).max;

    function setUp() public virtual {
        self = address(this);
        vm.chainId(1);

        // deploy core contracts
        escrow = new Escrow();
        address escrow_ = address(escrow);
        root = new Root(escrow_, 48 hours);
        address root_ = address(root);
        LiquidityPoolFactory liquidityPoolFactory = new LiquidityPoolFactory(root_);
        TrancheTokenFactory trancheTokenFactory = new TrancheTokenFactory(root_);
        evmInvestmentManager = new InvestmentManager(escrow_);
        address evmInvestmentManager_ = address(evmInvestmentManager);
        evmPoolManager = new PoolManager(escrow_, address(liquidityPoolFactory), address(trancheTokenFactory));
        address evmPoolManager_ = address(evmPoolManager);
        liquidityPoolFactory.rely(evmPoolManager_);
        trancheTokenFactory.rely(evmPoolManager_);

        // deploy mocks
        mockXcmRouter = new MockXcmRouter(evmInvestmentManager_);
        homePools = new MockHomeLiquidityPools(address(mockXcmRouter));
        erc20 = newErc20("X's Dollar", "USDX", 6);

        // gateway
        gateway = new Gateway(root_, evmInvestmentManager_, evmPoolManager_, address(mockXcmRouter));
        address gateway_ = address(gateway);

        // wire contracts

        evmInvestmentManager.file("gateway", gateway_);
        evmInvestmentManager.file("poolManager", evmPoolManager_);
        evmInvestmentManager.rely(gateway_);
        evmInvestmentManager.rely(evmPoolManager_);
        evmPoolManager.file("gateway", gateway_);
        evmPoolManager.file("investmentManager", evmInvestmentManager_);
        escrow.rely(evmInvestmentManager_);
        escrow.rely(evmPoolManager_);
        // escrow.rely(gateway_);
        mockXcmRouter.file("gateway", gateway_);
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
        uint8 decimals,
        string memory tokenName,
        string memory tokenSymbol,
        bytes16 trancheId,
        uint128 price,
        uint128 currency
    ) public returns (address) {
        homePools.addPool(poolId); // add pool
        homePools.addTranche(poolId, trancheId, tokenName, tokenSymbol, decimals, price); // add tranche
        homePools.addCurrency(currency, address(erc20));
        homePools.allowPoolCurrency(poolId, currency);
        evmPoolManager.deployTranche(poolId, trancheId);

        address lPoolAddress = evmPoolManager.deployLiquidityPool(poolId, trancheId, address(erc20));
        return lPoolAddress;
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
