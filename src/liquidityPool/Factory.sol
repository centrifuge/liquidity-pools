// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.18;

import { LiquidityPool } from "./LiquidityPool.sol";
import { Memberlist} from "../token/memberlist.sol";

interface ImmutableCreate2Factory {
    function safeCreate2(bytes32 salt, bytes calldata initCode) external payable returns (address deploymentAddress);
}

interface LiquidityPoolFactoryLike {
    function newLiquidityPool(uint64 _poolId, bytes16 _trancheId, uint128 _currencyId, address _asset, address _connector, address _admin, address _memberlist, string memory _name, string memory _symbol, uint8 _decimals) external returns (address);
}

contract LiquidityPoolFactory {
    function newLiquidityPool(uint64 _poolId, bytes16 _trancheId, uint128 _currencyId, address _asset, address _connector, address _admin, address _memberlist, string memory _name, string memory _symbol, uint8 _decimals)
        public
        returns (address)
    {
        // Salt is hash(poolId + trancheId + asset), to deploy copies of the restricted token contract
        // on multiple chains with the same address for the same tranche
        bytes32 salt = keccak256(abi.encodePacked(_poolId, _trancheId, _currencyId));

        LiquidityPool lPool = new LiquidityPool{salt: salt}(_decimals);

        // Name and symbol are not passed on constructor, such that if the same tranche is deployed
        // on another chain with a different name (it might have changed in between deployments),
        // then the address remains deterministic.
        lPool.file("name", _name);
        lPool.file("symbol", _symbol);
        lPool.file("connector", _connector);
        lPool.file("asset", _asset);
        lPool.file("memberlist", _memberlist);
        lPool.setPoolDetails(_poolId, _trancheId);

        lPool.deny(msg.sender);
        lPool.rely(_admin);
        lPool.rely(_connector); // to be able to update tokenPrices
        lPool.deny(address(this));
        return address(lPool);
    }
}

interface MemberlistFactoryLike {
    function newMemberlist(address _admin, address _connector) external returns (address);
}

contract MemberlistFactory {
    function newMemberlist(address _admin, address _connector) public returns (address memberList) {
        Memberlist memberlist = new Memberlist();

        
        memberlist.deny(msg.sender);
        memberlist.rely(_admin);
        memberlist.rely(_connector); // connector is updating members
        memberlist.deny(address(this));

        return (address(memberlist));
    }
}
