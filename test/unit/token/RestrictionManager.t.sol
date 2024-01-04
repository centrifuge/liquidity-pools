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
        restrictionManager.updateMember(address(this), block.timestamp - 1);

        restrictionManager.updateMember(address(this), validUntil);
        assertEq(restrictionManager.members(address(this)), validUntil);
    }

    function testIsMember(uint64 validUntil) public {
        vm.assume(validUntil >= block.timestamp);

        restrictionManager.updateMember(address(this), validUntil);
        assert(restrictionManager.hasMember(address(this)));
    }

    function testFreeze() public {
        restrictionManager.freeze(address(this));
        assertEq(restrictionManager.frozen(address(this)), 1);
    }

    function testFreezingZeroAddress() public {
        vm.expectRevert("RestrictionManager/cannot-freeze-zero-address");
        restrictionManager.freeze(address(0));
        assertEq(restrictionManager.frozen(address(0)), 0);
    }
}
