// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.18;

import {RestrictedToken} from "./restricted.sol";
import {Memberlist} from "./memberlist.sol";

interface ImmutableCreate2Factory {
    function safeCreate2(bytes32 salt, bytes calldata initCode) external payable returns (address deploymentAddress);
}

interface TrancheTokenFactoryLike {
    function newTrancheToken(uint64, bytes16, string calldata, string calldata, uint8) external returns (address);
}

contract TrancheTokenFactory {
    function newTrancheToken(uint64 poolId, bytes16 trancheId, string memory name, string memory symbol, uint8 decimals)
        public
        returns (address)
    {
        // Salt is hash(poolId + trancheId), to deploy copies of the restricted token contract
        // on multiple chains with the same address for the same tranche
        bytes32 salt = keccak256(abi.encodePacked(poolId, trancheId));

        RestrictedToken token = new RestrictedToken{salt: salt}(decimals);

        // Name and symbol are not passed on constructor, such that if the same tranche is deployed
        // on another chain with a different name (it might have changed in between deployments),
        // then the address remains deterministic.
        token.file("name", name);
        token.file("symbol", symbol);

        token.rely(msg.sender);
        token.deny(address(this));
        return address(token);
    }
}

interface MemberlistFactoryLike {
    function newMemberlist() external returns (address);
}

contract MemberlistFactory {
    function newMemberlist() public returns (address memberList) {
        Memberlist memberlist = new Memberlist();

        memberlist.rely(msg.sender);
        memberlist.deny(address(this));

        return (address(memberlist));
    }
}
