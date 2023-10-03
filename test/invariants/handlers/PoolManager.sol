// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import {MockCentrifugeChain} from "test/mock/MockCentrifugeChain.sol";
import {PoolManager} from "src/PoolManager.sol";
import {ERC20} from "src/token/ERC20.sol";
import "forge-std/Test.sol";

contract PoolManagerHandler is Test {
    uint64[] public allPools;
    bytes16[] public allTranches;
    address[] public allLiquidityPools;
    mapping(bytes16 => uint64) public trancheIdToPoolId;
    MockCentrifugeChain centrifugeChain;
    PoolManager poolManager;

    constructor(address centrifugeChain_, address poolManager_) {
        centrifugeChain = MockCentrifugeChain(centrifugeChain_);
        poolManager = PoolManager(poolManager_);
    }

    function addPool(uint64 poolId) public {
        centrifugeChain.addPool(poolId);

        allPools.push(poolId);
    }

    function addTranche(
        uint64 poolId,
        bytes16 trancheId,
        string memory tokenName,
        string memory tokenSymbol,
        uint8 decimals
    ) public {
        centrifugeChain.addTranche(poolId, trancheId, tokenName, tokenSymbol, decimals);

        allTranches.push(trancheId);
        trancheIdToPoolId[trancheId] = poolId;
    }

    function deployLiquidityPool(uint64 poolId, bytes16 trancheId, address currency) public {
        uint128 currencyId = 1;
        centrifugeChain.addCurrency(currencyId, currency);
        centrifugeChain.allowInvestmentCurrency(poolId, currencyId);
        address pool = poolManager.deployLiquidityPool(poolId, trancheId, currency);

        allLiquidityPools.push(pool);
    }

    function addPoolTrancheAndLiquidityPool(uint64 poolId, bytes16 trancheId, uint8 decimals) public {
        string memory tokenName = "tokenName";
        string memory tokenSymbol = "tokenSymbol";
        addPool(poolId);
        addTranche(poolId, trancheId, tokenName, tokenSymbol, decimals);
        address erc20 = address(_newErc20(tokenName, tokenSymbol, decimals));
        deployLiquidityPool(poolId, trancheId, erc20);
    }

    function allTranchesLength() public view returns (uint256) {
        return allTranches.length;
    }

    function allLiquidityPoolsLength() public view returns (uint256) {
        return allLiquidityPools.length;
    }

    function _newErc20(string memory name, string memory symbol, uint8 decimals) internal returns (ERC20) {
        ERC20 currency = new ERC20(decimals);
        currency.file("name", name);
        currency.file("symbol", symbol);
        return currency;
    }

    // Added to be ignored in coverage report
    function test() public {}
}