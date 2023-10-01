// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import {MockCentrifugeChain} from "test/mock/MockCentrifugeChain.sol";
import {TestSetup} from "test/TestSetup.t.sol";
import "forge-std/Test.sol";

contract InvariantPoolManager is TestSetup {
    uint64[] public allPools;
    bytes16[] public allTranches;
    address[] public allLiquidityPools;
    mapping(bytes16 => uint64) public trancheIdToPoolId;

    constructor(MockCentrifugeChain centrifugeChain_) {
        centrifugeChain = centrifugeChain_;
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

    // Added to be ignored in coverage report
    function test() public {}
}
