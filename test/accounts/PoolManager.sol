// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import {MockHomeLiquidityPools} from "../mock/MockHomeLiquidityPools.sol";
import "forge-std/Test.sol";

contract InvariantPoolManager is Test {
    MockHomeLiquidityPools immutable homePools;

    uint64[] public allPools;
    bytes16[] public allTranches;
    mapping(bytes16 => uint64) public trancheIdToPoolId;

    constructor(MockHomeLiquidityPools homePools_) {
        homePools = homePools_;
    }

    function addPool(uint64 poolId) public {
        homePools.addPool(poolId);

        allPools.push(poolId);
    }

    function addPoolAndTranche(uint64 poolId, bytes16 trancheId, uint8 decimals) public {
        addPool(poolId);
        homePools.addTranche(poolId, trancheId, "-", "-", decimals);

        allTranches.push(trancheId);
        trancheIdToPoolId[trancheId] = poolId;
    }

    function allTranchesLength() public view returns (uint256) {
        return allTranches.length;
    }

    // Added to be ignored in coverage report
    function test() public {}
}
