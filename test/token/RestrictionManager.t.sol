// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import {MemberlistLike, RestrictionManager} from "src/token/RestrictionManager.sol";
import "forge-std/Test.sol";

contract RestrictionManagerTest is Test {
    RestrictionManager restrictionManager;

    function setUp() public {
        restrictionManager = new RestrictionManager();
    }

    function testAddMember(uint64 validUntil) public {
        vm.assume(validUntil >= block.timestamp);

        restrictionManager.updateMember(address(this), validUntil);
        assertEq(restrictionManager.members(address(this)), validUntil);
    }

    function testAddMembers(uint64 validUntil) public {
        vm.assume(validUntil >= block.timestamp);

        address[] memory members = new address[](3);
        members[0] = address(1);
        members[1] = address(2);
        members[2] = address(3);

        restrictionManager.updateMembers(members, validUntil);
        assertEq(restrictionManager.members(address(1)), validUntil);
        assertEq(restrictionManager.members(address(2)), validUntil);
        assertEq(restrictionManager.members(address(3)), validUntil);
    }

    function testIsMember(uint64 validUntil) public {
        vm.assume(validUntil >= block.timestamp);

        restrictionManager.updateMember(address(this), validUntil);
        restrictionManager.member(address(this));
        assert(restrictionManager.hasMember(address(this)));
    }
}
