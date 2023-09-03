// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import {LiquidityPool} from "../LiquidityPool.sol";
import {TrancheToken} from "../token/Tranche.sol";
import {Memberlist} from "../token/Memberlist.sol";
import {Auth} from "./Auth.sol";

interface RootLike {
    function escrow() external view returns (address);
}

interface LiquidityPoolFactoryLike {
    function newLiquidityPool(
        uint64 poolId,
        bytes16 trancheId,
        address asset,
        address trancheToken,
        address investmentManager
    ) external returns (address);
}

contract LiquidityPoolFactory is Auth {
    address immutable root;

    constructor(address _root) {
        root = _root;

        wards[msg.sender] = 1;
        emit Rely(msg.sender);
    }

    function newLiquidityPool(
        uint64 poolId,
        bytes16 trancheId,
        address asset,
        address trancheToken,
        address poolManager
    ) public auth returns (address) {
        LiquidityPool liquidityPool = new LiquidityPool(poolId, trancheId, asset, trancheToken, poolManager);

        liquidityPool.rely(root);
        liquidityPool.rely(poolManager); // to be able to update tokenPrices
        liquidityPool.deny(address(this));
        return address(liquidityPool);
    }
}

interface TrancheTokenFactoryLike {
    function newTrancheToken(
        uint64 poolId,
        bytes16 trancheId,
        address poolManager,
        string memory name,
        string memory symbol,
        uint8 decimals
    ) external returns (address);
}

contract TrancheTokenFactory is Auth {
    address immutable root;

    constructor(address _root) {
        root = _root;

        wards[msg.sender] = 1;
        emit Rely(msg.sender);
    }

    function newTrancheToken(
        uint64 poolId,
        bytes16 trancheId,
        address poolManager,
        string memory name,
        string memory symbol,
        uint8 decimals
    ) public auth returns (address) {
        address memberlist = _newMemberlist(poolManager);

        // Salt is hash(poolId + trancheId)
        // same tranche token address on every evm chain
        bytes32 salt = keccak256(abi.encodePacked(poolId, trancheId));

        TrancheToken token = new TrancheToken{salt: salt}(decimals);

        token.file("name", name);
        token.file("symbol", symbol);
        token.file("memberlist", memberlist);

        token.rely(root);
        token.rely(poolManager); // to be able to update token prices
        token.deny(address(this));

        return address(token);
    }

    function _newMemberlist(address poolManager) internal returns (address memberList) {
        Memberlist memberlist = new Memberlist();

        memberlist.updateMember(RootLike(root).escrow(), type(uint256).max);

        memberlist.rely(root);
        memberlist.rely(poolManager); // to be able to add members
        memberlist.deny(address(this));

        return (address(memberlist));
    }
}
