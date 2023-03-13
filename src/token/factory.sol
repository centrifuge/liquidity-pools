// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.18;

import {RestrictedToken} from "./restricted.sol";
import {Memberlist} from "./memberlist.sol";

interface RestrictedTokenFactoryLike {
    function newRestrictedToken(string calldata, string calldata, uint8) external returns (address);
}

contract RestrictedTokenFactory {
    function newRestrictedToken(string memory name, string memory symbol, uint8 decimals) public returns (address) {
        RestrictedToken token = new RestrictedToken(name, symbol, decimals);
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
