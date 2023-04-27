// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.18;
pragma abicoder v2;

import {MockHomeConnector} from "../mock/MockHomeConnector.sol";
import "forge-std/Test.sol";

contract InvariantPoolManager is Test {
    MockHomeConnector connector;

    uint64[] public allPools;
    bytes16[] public allTranches;
    mapping(bytes16 => uint64) public trancheIdToPoolId;

    constructor(MockHomeConnector connector_) {
        connector = connector_;
    }

    function addPool(uint64 poolId) public {
        connector.addPool(poolId);

        allPools.push(poolId);
    }

    function addPoolAndTranche(uint64 poolId, bytes16 trancheId, uint8 decimals, uint128 price) public {
        addPool(poolId);
        connector.addTranche(poolId, trancheId, "-", "-", decimals, price);

        allTranches.push(trancheId);
        trancheIdToPoolId[trancheId] = poolId;
    }

    function allTranchesLength() public view returns (uint256) {
        return allTranches.length;
    }
}
