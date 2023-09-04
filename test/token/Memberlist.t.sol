// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import {MemberlistLike, Memberlist} from "src/token/Memberlist.sol";
import "forge-std/Test.sol";

contract MemberlistTest is Test {
    Memberlist memberlist;

    function setUp() public {
        memberlist = new Memberlist();
    }

    function testAddMember(uint64 validUntil) public {
        vm.assume(validUntil >= block.timestamp);

        memberlist.updateMember(address(this), validUntil);
        assertEq(memberlist.members(address(this)), validUntil);
    }

    function testAddMembers(uint64 validUntil) public {
        vm.assume(validUntil >= block.timestamp);
        
        address[] memory members = new address[](3);
        members[0] = address(1);
        members[1] = address(2);
        members[2] = address(3);

        memberlist.updateMembers(members, validUntil);
        assertEq(memberlist.members(address(1)), validUntil);
        assertEq(memberlist.members(address(2)), validUntil);
        assertEq(memberlist.members(address(3)), validUntil);
    }

    function testIsMember(uint64 validUntil) public {
        vm.assume(validUntil >= block.timestamp);
        
        memberlist.updateMember(address(this), validUntil);
        memberlist.member(address(this));
        assert(memberlist.hasMember(address(this)));
    }

}
