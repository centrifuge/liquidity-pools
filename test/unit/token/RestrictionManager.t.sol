// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import {Tranche} from "src/token/Tranche.sol";
import {MockRoot} from "test/mocks/MockRoot.sol";
import {IHook} from "src/interfaces/token/IHook.sol";
import {RestrictionManager} from "src/token/RestrictionManager.sol";
import {IERC165} from "src/interfaces/IERC7575.sol";
import "forge-std/Test.sol";

contract RestrictionManagerTest is Test {
    MockRoot root;
    Tranche token;
    RestrictionManager restrictionManager;

    function setUp() public {
        root = new MockRoot();
        token = new Tranche(18);
        restrictionManager = new RestrictionManager(address(root));
        token.file("hook", address(restrictionManager));
    }

    function testAddMember(uint64 validUntil) public {
        vm.assume(validUntil >= block.timestamp);

        vm.expectRevert("RestrictionManager/invalid-valid-until");
        restrictionManager.updateMember(address(token), address(this), uint64(block.timestamp - 1));

        restrictionManager.updateMember(address(token), address(this), validUntil);
        assertTrue(restrictionManager.isMember(address(token), address(this)));
    }

    function testIsMember(uint64 validUntil) public {
        vm.assume(validUntil >= block.timestamp);

        restrictionManager.updateMember(address(token), address(this), validUntil);
        assertTrue(restrictionManager.isMember(address(token), address(this)));
    }

    function testFreeze() public {
        restrictionManager.freeze(address(token), address(this));
        assertEq(restrictionManager.isFrozen(address(token), address(this)), true);
    }

    function testFreezingZeroAddress() public {
        vm.expectRevert("RestrictionManager/cannot-freeze-zero-address");
        restrictionManager.freeze(address(token), address(0));
        assertEq(restrictionManager.isFrozen(address(token), address(0)), false);
    }

    // --- erc165 checks ---
    function testERC165Support(bytes4 unsupportedInterfaceId) public {
        bytes4 erc165 = 0x01ffc9a7;
        bytes4 hook = 0x0ede2660;

        vm.assume(unsupportedInterfaceId != erc165 && unsupportedInterfaceId != hook);

        assertEq(type(IERC165).interfaceId, erc165);
        assertEq(type(IHook).interfaceId, hook);

        assertEq(restrictionManager.supportsInterface(erc165), true);
        assertEq(restrictionManager.supportsInterface(hook), true);

        assertEq(restrictionManager.supportsInterface(unsupportedInterfaceId), false);
    }
}
