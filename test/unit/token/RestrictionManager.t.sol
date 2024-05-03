// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import {TrancheToken} from "src/token/Tranche.sol";
import {RestrictionManagerLike, RestrictionManager} from "src/token/RestrictionManager.sol";
import "forge-std/Test.sol";

contract RestrictionManagerTest is Test {
    TrancheToken token;
    RestrictionManager restrictionManager;

    function setUp() public {
        token = new TrancheToken(18);
        restrictionManager = new RestrictionManager(address(token));
    }

    function testAddMember(uint64 validUntil) public {
        vm.assume(validUntil >= block.timestamp);

        vm.expectRevert("RestrictionManager/invalid-valid-until");
        restrictionManager.updateMember(address(this), uint64(block.timestamp - 1));

        restrictionManager.updateMember(address(this), validUntil);
        (, uint64 actualValidUntil) = restrictionManager.restrictions(address(this));
        assertEq(actualValidUntil, validUntil);
    }

    function testIsMember(uint64 validUntil) public {
        vm.assume(validUntil >= block.timestamp);

        restrictionManager.updateMember(address(this), validUntil);
        (, uint64 actualValidUntil) = restrictionManager.restrictions(address(this));
        assertTrue(actualValidUntil >= block.timestamp);
    }

    function testFreeze() public {
        restrictionManager.freeze(address(this));
        (bool frozen,) = restrictionManager.restrictions(address(this));
        assertEq(frozen, true);
    }

    function testFreezingZeroAddress() public {
        vm.expectRevert("RestrictionManager/cannot-freeze-zero-address");
        restrictionManager.freeze(address(0));
        (bool frozen,) = restrictionManager.restrictions(address(0));
        assertEq(frozen, false);
    }
}
