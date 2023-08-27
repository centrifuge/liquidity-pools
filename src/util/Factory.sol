// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.18;

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
        uint128 currencyId,
        address asset,
        address trancheToken,
        address investmentManager
    ) external returns (address);
}

contract LiquidityPoolFactory is Auth {
    address root;

    constructor(address _root) {
        root = _root;

        wards[msg.sender] = 1;
        emit Rely(msg.sender);
    }

    function newLiquidityPool(
        uint64 poolId,
        bytes16 trancheId,
        uint128 currencyId,
        address asset,
        address trancheToken,
        address investmentManager
    ) public auth returns (address) {
        // Salt is hash(poolId + trancheId + currencyId), to deploy copies of the liquidity pool contract
        // on multiple chains with the same address for the same tranche and asset
        bytes32 salt = keccak256(abi.encodePacked(poolId, trancheId, currencyId));

        LiquidityPool liquidityPool = new LiquidityPool{salt: salt}();

        // Name and symbol are not passed on constructor, such that if the same liquidity pool is deployed
        // on another chain with a different name (it might have changed in between deployments),
        // then the address remains deterministic.
        liquidityPool.file("investmentManager", investmentManager);
        liquidityPool.file("asset", asset);
        liquidityPool.file("share", trancheToken);
        liquidityPool.setPoolDetails(poolId, trancheId);

        liquidityPool.rely(root);
        liquidityPool.rely(investmentManager); // to be able to update tokenPrices
        liquidityPool.deny(address(this));
        return address(liquidityPool);
    }
}

interface TrancheTokenFactoryLike {
    function newTrancheToken(
        uint64 poolId,
        bytes16 trancheId,
        address investmentManager,
        address tokenManager,
        string memory name,
        string memory symbol,
        uint8 decimals
    ) external returns (address);
}

contract TrancheTokenFactory is Auth {
    address root;

    constructor(address _root) {
        root = _root;

        wards[msg.sender] = 1;
        emit Rely(msg.sender);
    }

    function newTrancheToken(
        uint64 poolId,
        bytes16 trancheId,
        address investmentManager,
        address tokenManager,
        string memory name,
        string memory symbol,
        uint8 decimals
    ) public auth returns (address) {
        address memberlist = _newMemberlist(tokenManager);

        // Salt is hash(poolId + trancheId)
        // same tranche token address on every evm chain
        bytes32 salt = keccak256(abi.encodePacked(poolId, trancheId));

        TrancheToken token = new TrancheToken{salt: salt}(decimals);

        token.file("name", name);
        token.file("symbol", symbol);
        token.file("memberlist", memberlist);

        token.rely(root);
        token.rely(investmentManager); // to be able to add LPs as wards
        token.rely(tokenManager); // to be able to update token prices
        token.deny(address(this));

        return address(token);
    }

    function _newMemberlist(address tokenManager) internal returns (address memberList) {
        Memberlist memberlist = new Memberlist();

        memberlist.updateMember(RootLike(root).escrow(), type(uint256).max);

        memberlist.rely(root);
        memberlist.rely(tokenManager); // to be able to add members
        memberlist.deny(address(this));

        return (address(memberlist));
    }
}
