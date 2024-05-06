// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import {TrancheToken} from "src/token/Tranche.sol";
import {RestrictionSetLike, RestrictionSet01} from "src/token/RestrictionSet01.sol";
import "forge-std/Test.sol";

contract RestrictionSet01Test is Test {
    TrancheToken token;
    RestrictionSet01 restrictionManager;

    function setUp() public {
        token = new TrancheToken(18);
        restrictionManager = new RestrictionSet01(address(token), makeAddr("Escrow"));
    }

    function testAddMember(uint64 validUntil) public {
        vm.assume(validUntil >= block.timestamp);

        vm.expectRevert("RestrictionSet01/invalid-valid-until");
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
        vm.expectRevert("RestrictionSet01/cannot-freeze-zero-address");
        restrictionManager.freeze(address(0));
        (bool frozen,) = restrictionManager.restrictions(address(0));
        assertEq(frozen, false);
    }
}
