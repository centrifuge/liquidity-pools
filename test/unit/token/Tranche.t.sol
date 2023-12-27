// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import {TrancheToken} from "src/token/Tranche.sol";
import {RestrictionManagerLike} from "src/token/RestrictionManager.sol";
import {RestrictionManagerMock} from "test/mocks/RestrictionManager.sol";
import "forge-std/Test.sol";

interface ERC20Like {
    function balanceOf(address) external view returns (uint256);
}

contract TrancheTokenTest is Test {
    TrancheToken token;
    RestrictionManagerMock restrictionManager;

    address self;
    address targetUser = makeAddr("targetUser");
    address randomUser = makeAddr("random");
    uint256 validUntil = block.timestamp + 7 days;

    function setUp() public {
        self = address(this);
        token = new TrancheToken(18);
        token.file("name", "Some Token");
        token.file("symbol", "ST");

        restrictionManager = new RestrictionManagerMock(address(token));
        restrictionManager.rely(address(token));
        token.file("restrictionManager", address(restrictionManager));
    }

    // --- Admnistration ---

    function testFile() public {
        // fail: unrecognized param
        vm.expectRevert(bytes("TrancheToken/file-unrecognized-param"));
        token.file("random", self);

        // success
        token.file("restrictionManager", self);
        assertEq(address(token.restrictionManager()), self);

        // remove self from wards
        token.deny(self);
        // auth fail
        vm.expectRevert(bytes("Auth/not-authorized"));
        token.file("restrictionManager", self);
    }

    // --- TrustedForwarder ---
    function testAddLiquidityPool() public {
        assertTrue(!token.isTrustedForwarder(self));

        //success
        token.addTrustedForwarder(self);
        assertTrue(token.isTrustedForwarder(self));

        // remove self from wards
        token.deny(self);
        // auth fail
        vm.expectRevert(bytes("Auth/not-authorized"));
        token.addTrustedForwarder(self);
    }

    function testRemoveLiquidityPool() public {
        token.addTrustedForwarder(self);
        assertTrue(token.isTrustedForwarder(self));

        // success
        token.removeTrustedForwarder(self);
        assertTrue(!token.isTrustedForwarder(self));

        // remove self from wards
        token.deny(self);
        // auth fail
        vm.expectRevert(bytes("Auth/not-authorized"));
        token.removeTrustedForwarder(self);
    }

    function testCheckTrustedForwarderWorks(uint256 amount) public {
        vm.assume(amount > 0);

        assertTrue(!token.isTrustedForwarder(self));
        // make self trusted forwarder
        token.addTrustedForwarder(self);
        assertTrue(token.isTrustedForwarder(self));
        // add self to restrictionManager
        restrictionManager.updateMember(self, validUntil);
        restrictionManager.updateMember(randomUser, validUntil);

        bool success;
        // test auth works with trustedForwarder
        // fail -> randomUser not ward
        (success,) = address(token).call(
            abi.encodeWithSelector(bytes4(keccak256(bytes("mint(address,uint256)"))), self, amount, randomUser)
        );
        assertTrue(!success);
        assertEq(token.balanceOf(self), 0);

        // success -> self is ward
        (success,) = address(token).call(
            abi.encodeWithSelector(bytes4(keccak256(bytes("mint(address,uint256)"))), self, amount, self)
        );
        assertTrue(success);
        assertEq(token.balanceOf(self), amount);

        // test non auth function works with trusted forwarder
        // fail -> randomUser has no balance
        (success,) = address(token).call(
            abi.encodeWithSelector(bytes4(keccak256(bytes("transfer(address,uint256)"))), self, amount, randomUser)
        );

        assertTrue(!success);
        assertEq(token.balanceOf(self), amount);

        // success -> self has enough balance to transfer
        (success,) = address(token).call(
            abi.encodeWithSelector(bytes4(keccak256(bytes("transfer(address,uint256)"))), randomUser, amount, self)
        );

        assertTrue(success);
        assertEq(token.balanceOf(self), 0);
        assertEq(token.balanceOf(randomUser), amount);
    }

    // --- RestrictionManager ---
    // transferFrom
    function testTransferFrom(uint256 amount) public {
        restrictionManager.updateMember(self, validUntil);
        token.mint(self, amount);

        vm.expectRevert(bytes("RestrictionManager/destination-not-a-member"));
        token.transferFrom(self, targetUser, amount);
        assertEq(token.balanceOf(targetUser), 0);

        restrictionManager.updateMember(targetUser, validUntil);
        assertEq(restrictionManager.members(targetUser), validUntil);

        restrictionManager.freeze(self);
        vm.expectRevert(bytes("RestrictionManager/source-is-frozen"));
        token.transferFrom(self, targetUser, amount);
        assertEq(token.balanceOf(targetUser), 0);

        restrictionManager.unfreeze(self);
        token.transferFrom(self, targetUser, amount);
        assertEq(token.balanceOf(targetUser), amount);
        afterTransferAssumptions(self, targetUser, amount);

        vm.warp(validUntil + 1);
        vm.expectRevert(bytes("RestrictionManager/destination-not-a-member"));
        token.transferFrom(self, targetUser, amount);
    }

    function testTransferFromTokensWithApproval(uint256 amount) public {
        vm.assume(amount > 0);
        address sender = makeAddr("sender");
        restrictionManager.updateMember(sender, validUntil);
        token.mint(sender, amount);

        restrictionManager.updateMember(targetUser, validUntil);

        vm.expectRevert(bytes("ERC20/insufficient-allowance"));
        token.transferFrom(sender, targetUser, amount);

        vm.prank(sender);
        token.approve(self, amount);
        token.transferFrom(sender, targetUser, amount);
        assertEq(token.balanceOf(targetUser), amount);
        assertEq(token.balanceOf(sender), 0);
        afterTransferAssumptions(sender, targetUser, amount);
    }

    // transfer
    function testTransfer(uint256 amount) public {
        restrictionManager.updateMember(self, validUntil);
        token.mint(self, amount);

        vm.expectRevert(bytes("RestrictionManager/destination-not-a-member"));
        token.transfer(targetUser, amount);
        assertEq(token.balanceOf(targetUser), 0);

        restrictionManager.updateMember(targetUser, validUntil);
        assertEq(restrictionManager.members(targetUser), validUntil);

        restrictionManager.freeze(self);
        vm.expectRevert(bytes("RestrictionManager/source-is-frozen"));
        token.transfer(targetUser, amount);
        assertEq(token.balanceOf(targetUser), 0);

        restrictionManager.unfreeze(self);
        token.transfer(targetUser, amount);
        assertEq(token.balanceOf(targetUser), amount);
        afterTransferAssumptions(self, targetUser, amount);

        vm.warp(validUntil + 1);
        vm.expectRevert(bytes("RestrictionManager/destination-not-a-member"));
        token.transfer(targetUser, amount);
    }

    // auth transfer
    function testAuthTransferFrom(uint256 amount) public {
        address sourceUser = makeAddr("sourceUser");
        restrictionManager.updateMember(sourceUser, validUntil);
        token.mint(sourceUser, amount);

        vm.prank(address(2));
        vm.expectRevert(bytes("Auth/not-authorized"));
        token.authTransferFrom(sourceUser, self, amount);
        assertEq(token.balanceOf(sourceUser), amount);
        assertEq(token.balanceOf(self), 0);

        token.authTransferFrom(sourceUser, self, amount);
        assertEq(token.balanceOf(sourceUser), 0);
        assertEq(token.balanceOf(self), amount);
    }

    // mint
    function testMintTokensToMemberWorks(uint256 amount) public {
        // mint fails -> self not a member
        vm.expectRevert(bytes("RestrictionManager/destination-not-a-member"));
        token.mint(targetUser, amount);

        restrictionManager.updateMember(targetUser, validUntil);
        assertEq(restrictionManager.members(targetUser), validUntil);

        restrictionManager.freeze(self);
        vm.expectRevert(bytes("RestrictionManager/source-is-frozen"));
        token.mint(targetUser, amount);
        assertEq(token.balanceOf(targetUser), 0);

        restrictionManager.unfreeze(self);
        token.mint(targetUser, amount);
        assertEq(token.balanceOf(targetUser), amount);
        afterMintAssumptions(targetUser, amount);

        vm.warp(validUntil + 1);

        vm.expectRevert(bytes("RestrictionManager/destination-not-a-member"));
        token.mint(targetUser, amount);
    }

    function testTransferMintFailsNoPermissionOnRestrictionManager() public {
        uint256 amount = 100;
        restrictionManager.updateMember(self, validUntil);
        token.mint(self, amount);

        restrictionManager.updateMember(targetUser, validUntil);
        assertEq(restrictionManager.members(targetUser), validUntil);

        restrictionManager.deny(address(token)); // remove permissions on restrictionManager - not able to call after
            // transfer / mint functions

        vm.expectRevert(bytes("Auth/not-authorized"));
        token.transferFrom(self, targetUser, amount);

        vm.expectRevert(bytes("Auth/not-authorized"));
        token.transfer(targetUser, amount);

        vm.expectRevert(bytes("Auth/not-authorized"));
        token.mint(targetUser, amount);
    }

    function afterTransferAssumptions(address from, address to, uint256 amount) internal {
        assertEq(restrictionManager.values_address("transfer_from"), from);
        assertEq(restrictionManager.values_address("transfer_to"), to);
        assertEq(restrictionManager.values_uint256("transfer_amount"), amount);
    }

    function afterMintAssumptions(address to, uint256 amount) internal {
        assertEq(restrictionManager.values_address("mint_to"), to);
        assertEq(restrictionManager.values_uint256("mint_amount"), amount);
    }
}
