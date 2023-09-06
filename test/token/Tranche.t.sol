// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import {TrancheToken} from "src/token/Tranche.sol";
import {MemberlistLike, RestrictionManager} from "src/token/RestrictionManager.sol";
import "forge-std/Test.sol";

interface ERC20Like {
    function balanceOf(address) external view returns (uint256);
}

contract TrancheTokenTest is Test {
    TrancheToken token;
    RestrictionManager restrictionManager;

    address self;

    function setUp() public {
        self = address(this);
        token = new TrancheToken(18);
        token.file("name", "Some Token");
        token.file("symbol", "ST");

        restrictionManager = new RestrictionManager();
        token.file("restrictionManager", address(restrictionManager));

        restrictionManager.updateMember(address(this), type(uint256).max);
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
        token.addLiquidityPool(self);
        assertTrue(token.isTrustedForwarder(self));

        // remove self from wards
        token.deny(self);
        // auth fail
        vm.expectRevert(bytes("Auth/not-authorized"));
        token.addLiquidityPool(self);
    }

    function testRemoveLiquidityPool() public {
        token.addLiquidityPool(self);
        assertTrue(token.isTrustedForwarder(self));

        // success
        token.removeLiquidityPool(self);
        assertTrue(!token.isTrustedForwarder(self));

        // remove self from wards
        token.deny(self);
        // auth fail
        vm.expectRevert(bytes("Auth/not-authorized"));
        token.removeLiquidityPool(self);
    }

    function testCheckTrustedForwarderWorks(uint256 validUntil, uint256 amount, address random) public {
        vm.assume(validUntil > block.timestamp);
        vm.assume(amount > 0);
        vm.assume(random != address(0));
        vm.assume(random != address(token));

        assertTrue(!token.isTrustedForwarder(self));
        // make self trusted forwarder
        token.addLiquidityPool(self);
        assertTrue(token.isTrustedForwarder(self));
        // add self to restrictionManager
        restrictionManager.updateMember(self, validUntil);
        restrictionManager.updateMember(random, validUntil);

        bool success;
        // test auth works with trustedForwarder
        // fail -> random not ward
        (success,) = address(token).call(
            abi.encodeWithSelector(bytes4(keccak256(bytes("mint(address,uint256)"))), self, amount, random)
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
        // fail -> random has no balance
        (success,) = address(token).call(
            abi.encodeWithSelector(bytes4(keccak256(bytes("transfer(address,uint256)"))), self, amount, random)
        );

        assertTrue(!success);
        assertEq(token.balanceOf(self), amount);

        // success -> self has enough balance to transfer
        (success,) = address(token).call(
            abi.encodeWithSelector(bytes4(keccak256(bytes("transfer(address,uint256)"))), random, amount, self)
        );

        assertTrue(success);
        assertEq(token.balanceOf(self), 0);
        assertEq(token.balanceOf(random), amount);
    }

    // --- RestrictionManager ---
    // transferFrom
    function testTransferFromTokensToMemberWorks(uint256 amount, address targetUser, uint256 validUntil) public {
        vm.assume(baseAssumptions(validUntil, targetUser));

        restrictionManager.updateMember(targetUser, validUntil);
        assertEq(restrictionManager.members(targetUser), validUntil);

        token.mint(address(this), amount);
        token.transferFrom(address(this), targetUser, amount);
        assertEq(token.balanceOf(targetUser), amount);
    }

    function testTransferFromTokensToNonMemberFails(uint256 amount, address targetUser, uint256 validUntil) public {
        vm.assume(baseAssumptions(validUntil, targetUser));
        token.mint(address(this), amount);
        vm.expectRevert(bytes("RestrictionManager/destination-not-a-member"));
        token.transferFrom(address(this), targetUser, amount);
        assertEq(token.balanceOf(targetUser), 0);
    }

    function testTransferFromTokensToExpiredMemberFails(uint256 amount, address targetUser) public {
        vm.assume(targetUser != address(0) && targetUser != address(this) && targetUser != address(token));

        restrictionManager.updateMember(targetUser, block.timestamp);
        assertEq(restrictionManager.members(targetUser), block.timestamp);

        vm.warp(block.timestamp + 1);

        token.mint(address(this), amount);
        vm.expectRevert(bytes("RestrictionManager/destination-not-a-member"));
        token.transferFrom(address(this), targetUser, amount);
        assertEq(token.balanceOf(targetUser), 0);
    }

    // Transfer
    function testTransferTokensToMemberWorks(uint256 amount, address targetUser, uint256 validUntil) public {
        vm.assume(baseAssumptions(validUntil, targetUser));

        restrictionManager.updateMember(targetUser, validUntil);
        assertEq(restrictionManager.members(targetUser), validUntil);

        token.mint(address(this), amount);
        token.transfer(targetUser, amount);
        assertEq(token.balanceOf(targetUser), amount);
    }

    function testTransferTokensToNonMemberFails(uint256 amount, address targetUser, uint256 validUntil) public {
        vm.assume(baseAssumptions(validUntil, targetUser));

        token.mint(address(this), amount);
        vm.expectRevert(bytes("RestrictionManager/destination-not-a-member"));
        token.transfer(targetUser, amount);
        assertEq(token.balanceOf(targetUser), 0);
    }

    function testTransferTokensToExpiredMemberFails(uint256 amount, address targetUser) public {
        vm.assume(targetUser != address(0) && targetUser != address(this) && targetUser != address(token));

        restrictionManager.updateMember(targetUser, block.timestamp);
        assertEq(restrictionManager.members(targetUser), block.timestamp);

        vm.warp(block.timestamp + 1);

        token.mint(address(this), amount);
        vm.expectRevert(bytes("RestrictionManager/destination-not-a-member"));
        token.transfer(targetUser, amount);
        assertEq(token.balanceOf(targetUser), 0);
    }

    // Mint
    function testMintTokensToMemberWorks(uint256 amount, address targetUser, uint256 validUntil) public {
        vm.assume(baseAssumptions(validUntil, targetUser));

        restrictionManager.updateMember(targetUser, validUntil);
        assertEq(restrictionManager.members(targetUser), validUntil);

        token.mint(targetUser, amount);
        assertEq(token.balanceOf(targetUser), amount);
    }

    function testMintTokensToNonMemberFails(uint256 amount, address targetUser, uint256 validUntil) public {
        vm.assume(baseAssumptions(validUntil, targetUser));

        vm.expectRevert(bytes("RestrictionManager/destination-not-a-member"));
        token.mint(targetUser, amount);
        assertEq(token.balanceOf(targetUser), 0);
    }

    function testMintTokensToExpiredMemberFails(uint256 amount, address targetUser) public {
        vm.assume(targetUser != address(0) && targetUser != address(this) && targetUser != address(token));

        restrictionManager.updateMember(targetUser, block.timestamp);
        assertEq(restrictionManager.members(targetUser), block.timestamp);

        vm.warp(block.timestamp + 1);

        vm.expectRevert(bytes("RestrictionManager/destination-not-a-member"));
        token.mint(targetUser, amount);
        assertEq(token.balanceOf(targetUser), 0);
    }

    function baseAssumptions(uint256 validUntil, address targetUser) internal view returns (bool) {
        return validUntil > block.timestamp && targetUser != address(0) && targetUser != address(this)
            && targetUser != address(token);
    }
}
