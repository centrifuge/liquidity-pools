// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.18;

import {LiquidityPool} from "./LiquidityPool.sol";
import {RestrictedToken} from "../token/Restricted.sol";
import {Memberlist} from "../token/Memberlist.sol";

interface LiquidityPoolFactoryLike {
    function newLiquidityPool(
        uint64 _poolId,
        bytes16 _trancheId,
        uint128 _currencyId,
        address _asset,
        address _tranche,
        address _investmentManager,
        address _admin
    ) external returns (address);
}

interface TrancheTokenFactoryLike {
    function newTrancheToken(
        uint64 _poolId,
        bytes16 _trancheId,
        address _investmentManager,
        address _memberlist,
        string memory _name,
        string memory _symbol,
        uint8 _decimals,
        address _admin
    ) external returns (address);
}

contract LiquidityPoolFactory {
    function newLiquidityPool(
        uint64 _poolId,
        bytes16 _trancheId,
        uint128 _currencyId,
        address _asset,
        address _tranche,
        address _investmentManager,
        address _admin
    ) public returns (address) {
        // Salt is hash(poolId + trancheId + asset), to deploy copies of the liquidity pool contract
        // on multiple chains with the same address for the same tranche and asset
        bytes32 salt = keccak256(abi.encodePacked(_poolId, _trancheId, _currencyId));

        LiquidityPool lPool = new LiquidityPool{salt: salt}();

        // Name and symbol are not passed on constructor, such that if the same liquidity pool is deployed
        // on another chain with a different name (it might have changed in between deployments),
        // then the address remains deterministic.
        lPool.file("investmentManager", _investmentManager);
        lPool.file("asset", _asset);
        lPool.file("share", _tranche);
        lPool.setPoolDetails(_poolId, _trancheId);

        lPool.deny(msg.sender);
        lPool.rely(_admin);
        lPool.rely(_investmentManager); // to be able to update tokenPrices
        lPool.deny(address(this));
        return address(lPool);
    }
}

contract TrancheTokenFactory {
    function newTrancheToken(
        uint64 _poolId,
        bytes16 _trancheId,
        address _investmentManager,
        address _memberlist,
        string memory _name,
        string memory _symbol,
        uint8 _decimals,
        address _admin
    ) public returns (address) {
        // Salt is hash(poolId + trancheId )
        // same tracnhe token address on every evm chain
        bytes32 salt = keccak256(abi.encodePacked(_poolId, _trancheId));

        RestrictedToken token = new RestrictedToken{salt: salt}(_decimals);

        token.file("name", _name);
        token.file("symbol", _symbol);
        token.file("memberlist", _memberlist);

        token.deny(msg.sender);
        token.rely(_admin);
        token.rely(_investmentManager); // to be able to update tokenPrices
        token.deny(address(this));
        return address(token);
    }
}

interface MemberlistFactoryLike {
    function newMemberlist(address _admin, address _investmentManager) external returns (address);
}

contract MemberlistFactory {
    function newMemberlist(address _admin, address _investmentManager) public returns (address memberList) {
        Memberlist memberlist = new Memberlist();

        memberlist.rely(_admin);
        memberlist.rely(_investmentManager);
        memberlist.deny(address(this));

        return (address(memberlist));
    }
}
