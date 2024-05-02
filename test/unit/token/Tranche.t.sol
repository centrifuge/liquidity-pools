// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import {TrancheToken} from "src/token/Tranche.sol";
import {RestrictionManagerLike} from "src/token/RestrictionManager.sol";
import {MockRestrictionManager} from "test/mocks/MockRestrictionManager.sol";
import "forge-std/Test.sol";

interface ERC20Like {
    function balanceOf(address) external view returns (uint256);
}

contract TrancheTokenTest is Test {
    TrancheToken token;
    MockRestrictionManager restrictionManager;

    address self;
    address targetUser = makeAddr("targetUser");
    address randomUser = makeAddr("random");
    uint64 validUntil = uint64(block.timestamp + 7 days);

    function setUp() public {
        self = address(this);
        token = new TrancheToken(18);
        token.file("name", "Some Token");
        token.file("symbol", "ST");

        restrictionManager = new MockRestrictionManager(address(token));
        restrictionManager.rely(address(token));
        token.file("restrictionManager", address(restrictionManager));
    }

    // --- Admnistration ---

    function testFile(address asset, address vault) public {
        // fail: unrecognized param
        vm.expectRevert(bytes("TrancheToken/file-unrecognized-param"));
        token.file("random", self);

        vm.expectRevert(bytes("TrancheToken/file-unrecognized-param"));
        token.file("random", self, self);

        vm.expectRevert(bytes("TrancheToken/file-unrecognized-param"));
        token.file("random", self, false);

        // success
        token.file("restrictionManager", self);
        assertEq(address(token.restrictionManager()), self);

        token.file("vault", asset, vault);
        assertEq(address(token.vault(asset)), vault);

        // remove self from wards
        token.deny(self);

        // auth fail
        vm.expectRevert(bytes("Auth/not-authorized"));
        token.file("restrictionManager", self);

        vm.expectRevert(bytes("Auth/not-authorized"));
        token.file("vault", asset, vault);
    }

    // --- TrustedForwarder ---
    function testAddTrustedForwarder(address trustedForwarder) public {
        vm.assume(trustedForwarder != self);

        assertTrue(!token.isTrustedForwarder(trustedForwarder));

        //success
        token.file("trustedForwarder", trustedForwarder, true);
        assertTrue(token.isTrustedForwarder(trustedForwarder));

        // remove self from wards
        token.deny(self);
        // auth fail
        vm.expectRevert(bytes("Auth/not-authorized"));
        token.file("trustedForwarder", trustedForwarder, true);
    }

    function testRemoveTrustedForwarder(address trustedForwarder) public {
        vm.assume(trustedForwarder != self);

        token.file("trustedForwarder", trustedForwarder, true);
        assertTrue(token.isTrustedForwarder(trustedForwarder));

        // success
        token.file("trustedForwarder", trustedForwarder, false);
        assertTrue(!token.isTrustedForwarder(trustedForwarder));

        // remove self from wards
        token.deny(self);
        // auth fail
        vm.expectRevert(bytes("Auth/not-authorized"));
        token.file("trustedForwarder", trustedForwarder, false);
    }

    function testCheckTrustedForwarderWorks(uint256 amount) public {
        vm.assume(amount > 0);

        assertTrue(!token.isTrustedForwarder(self));
        // make self trusted forwarder
        token.file("trustedForwarder", self, true);
        assertTrue(token.isTrustedForwarder(self));
        // add self to restrictionManager
        restrictionManager.updateMember(self, uint64(validUntil));
        restrictionManager.updateMember(randomUser, uint64(validUntil));

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
        restrictionManager.updateMember(self, uint64(validUntil));
        token.mint(self, amount);

        vm.expectRevert(bytes("RestrictionManager/destination-not-a-member"));
        token.transferFrom(self, targetUser, amount);
        assertEq(token.balanceOf(targetUser), 0);

        restrictionManager.updateMember(targetUser, uint64(validUntil));
        (, uint64 actualValidUntil) = restrictionManager.restrictions(targetUser);
        assertEq(actualValidUntil, validUntil);

        restrictionManager.freeze(self);
        vm.expectRevert(bytes("RestrictionManager/source-is-frozen"));
        token.transferFrom(self, targetUser, amount);
        assertEq(token.balanceOf(targetUser), 0);

        restrictionManager.unfreeze(self);
        restrictionManager.freeze(targetUser);
        vm.expectRevert(bytes("RestrictionManager/destination-is-frozen"));
        token.transferFrom(self, targetUser, amount);
        assertEq(token.balanceOf(targetUser), 0);

        restrictionManager.unfreeze(targetUser);
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
        restrictionManager.updateMember(sender, uint64(validUntil));
        token.mint(sender, amount);

        restrictionManager.updateMember(targetUser, uint64(validUntil));

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
        restrictionManager.updateMember(self, uint64(validUntil));
        token.mint(self, amount);

        vm.expectRevert(bytes("RestrictionManager/destination-not-a-member"));
        token.transfer(targetUser, amount);
        assertEq(token.balanceOf(targetUser), 0);

        restrictionManager.updateMember(targetUser, uint64(validUntil));
        (, uint64 actualValidUntil) = restrictionManager.restrictions(targetUser);
        assertEq(actualValidUntil, validUntil);

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
        restrictionManager.updateMember(sourceUser, uint64(validUntil));
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

        restrictionManager.updateMember(targetUser, uint64(validUntil));
        (, uint64 actualValidUntil) = restrictionManager.restrictions(targetUser);
        assertEq(actualValidUntil, validUntil);

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
        restrictionManager.updateMember(self, uint64(validUntil));
        token.mint(self, amount);

        restrictionManager.updateMember(targetUser, uint64(validUntil));
        (, uint64 actualValidUntil) = restrictionManager.restrictions(targetUser);
        assertEq(actualValidUntil, validUntil);

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
