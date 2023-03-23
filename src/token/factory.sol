// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.18;

import {RestrictedToken} from "./restricted.sol";
import {Memberlist} from "./memberlist.sol";

interface ImmutableCreate2Factory {
    function safeCreate2(bytes32 salt, bytes calldata initCode) external payable returns (address deploymentAddress);
}

interface RestrictedTokenFactoryLike {
    function newRestrictedToken(uint64, bytes16, string calldata, string calldata, uint8) external returns (address);
}

contract RestrictedTokenFactory {
    ImmutableCreate2Factory immutable create2Factory = ImmutableCreate2Factory(0x0000000000FFe8B47B3e2130213B802212439497);

// uint64 poolId, bytes16 trancheId, 
    function newRestrictedToken(uint64 poolId, bytes16 trancheId, string memory name, string memory symbol, uint8 decimals) public returns (address) {
        bytes32 salt = bytes32(abi.encodePacked(0x0000000000000000000000000000000000000000, keccak256(abi.encodePacked(poolId, trancheId))));
        bytes memory initCode = getInitCode(name, symbol, decimals);

        RestrictedToken token = RestrictedToken(create2Factory.safeCreate2(salt, initCode));
        token.rely(msg.sender);
        token.deny(address(this));
        return address(token);
    }

    function getInitCode(string memory name, string memory symbol, uint8 decimals) public pure returns (bytes memory) {
        bytes memory bytecode = type(RestrictedToken).creationCode;
        return abi.encodePacked(bytecode, abi.encode(name), abi.encode(symbol), abi.encode(decimals));
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
