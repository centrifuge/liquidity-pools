// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.18;
pragma abicoder v2;

import {RestrictedTokenFactory, MemberlistFactory} from "src/token/factory.sol";
import {RestrictedTokenLike} from "src/token/restricted.sol";
import {MemberlistLike, Memberlist} from "src/token/memberlist.sol";
import "forge-std/Test.sol";

interface ERC20Like {
    function balanceOf(address) external view returns (uint256);
}

contract RestrictedTokenTest is Test {
    RestrictedTokenLike token;
    MemberlistLike memberlist;

    function setUp() public {
        RestrictedTokenFactory tokenFactory = new RestrictedTokenFactory();
        MemberlistFactory memberlistFactory = new MemberlistFactory();

        token = RestrictedTokenLike(tokenFactory.newRestrictedToken("Some Token", "ST", 18));

        memberlist = MemberlistLike(memberlistFactory.newMemberlist());
        token.file("memberlist", address(memberlist));

        memberlist.updateMember(address(this), type(uint256).max);
    }

    // transferFrom
    function testTransferFromTokensToMemberWorks(uint256 amount, address targetUser, uint256 validUntil) public {
        vm.assume(
            validUntil > block.timestamp && targetUser != address(0) && targetUser != address(this)
                && targetUser != address(token)
        );

        memberlist.updateMember(targetUser, validUntil);
        assertEq(memberlist.members(targetUser), validUntil);

        token.mint(address(this), amount);
        token.transferFrom(address(this), targetUser, amount);
        assertEq(token.balanceOf(targetUser), amount);
    }

    function testTransferFromTokensToNonMemberFails(uint256 amount, address targetUser, uint256 validUntil) public {
        vm.assume(
            validUntil > block.timestamp && targetUser != address(0) && targetUser != address(this)
                && targetUser != address(token)
        );

        token.mint(address(this), amount);
        vm.expectRevert(bytes("RestrictedToken/not-allowed-to-hold-token"));
        token.transferFrom(address(this), targetUser, amount);
        assertEq(token.balanceOf(targetUser), 0);
    }

    function testTransferFromTokensToExpiredMemberFails(uint256 amount, address targetUser) public {
        vm.assume(targetUser != address(0) && targetUser != address(this) && targetUser != address(token));

        memberlist.updateMember(targetUser, block.timestamp);
        assertEq(memberlist.members(targetUser), block.timestamp);

        vm.warp(block.timestamp + 1);

        token.mint(address(this), amount);
        vm.expectRevert(bytes("RestrictedToken/not-allowed-to-hold-token"));
        token.transferFrom(address(this), targetUser, amount);
        assertEq(token.balanceOf(targetUser), 0);
    }

    // Transfer
    function testTransferTokensToMemberWorks(uint256 amount, address targetUser, uint256 validUntil) public {
        vm.assume(
            validUntil > block.timestamp && targetUser != address(0) && targetUser != address(this)
                && targetUser != address(token)
        );

        memberlist.updateMember(targetUser, validUntil);
        assertEq(memberlist.members(targetUser), validUntil);

        token.mint(address(this), amount);
        token.transfer(targetUser, amount);
        assertEq(token.balanceOf(targetUser), amount);
    }

    function testTransferTokensToNonMemberFails(uint256 amount, address targetUser, uint256 validUntil) public {
        vm.assume(
            validUntil > block.timestamp && targetUser != address(0) && targetUser != address(this)
                && targetUser != address(token)
        );

        token.mint(address(this), amount);
        vm.expectRevert(bytes("RestrictedToken/not-allowed-to-hold-token"));
        token.transfer(targetUser, amount);
        assertEq(token.balanceOf(targetUser), 0);
    }

    function testTransferTokensToExpiredMemberFails(uint256 amount, address targetUser) public {
        vm.assume(targetUser != address(0) && targetUser != address(this) && targetUser != address(token));

        memberlist.updateMember(targetUser, block.timestamp);
        assertEq(memberlist.members(targetUser), block.timestamp);

        vm.warp(block.timestamp + 1);

        token.mint(address(this), amount);
        vm.expectRevert(bytes("RestrictedToken/not-allowed-to-hold-token"));
        token.transfer(targetUser, amount);
        assertEq(token.balanceOf(targetUser), 0);
    }

    // Mint
    function testMintTokensToMemberWorks(uint256 amount, address targetUser, uint256 validUntil) public {
        vm.assume(
            validUntil > block.timestamp && targetUser != address(0) && targetUser != address(this)
                && targetUser != address(token)
        );

        memberlist.updateMember(targetUser, validUntil);
        assertEq(memberlist.members(targetUser), validUntil);

        token.mint(targetUser, amount);
        assertEq(token.balanceOf(targetUser), amount);
    }

    function testMintTokensToNonMemberFails(uint256 amount, address targetUser, uint256 validUntil) public {
        vm.assume(
            validUntil > block.timestamp && targetUser != address(0) && targetUser != address(this)
                && targetUser != address(token)
        );

        vm.expectRevert(bytes("RestrictedToken/not-allowed-to-hold-token"));
        token.mint(targetUser, amount);
        assertEq(token.balanceOf(targetUser), 0);
    }

    function testMintTokensToExpiredMemberFails(uint256 amount, address targetUser) public {
        vm.assume(targetUser != address(0) && targetUser != address(this) && targetUser != address(token));

        memberlist.updateMember(targetUser, block.timestamp);
        assertEq(memberlist.members(targetUser), block.timestamp);

        vm.warp(block.timestamp + 1);

        vm.expectRevert(bytes("RestrictedToken/not-allowed-to-hold-token"));
        token.mint(targetUser, amount);
        assertEq(token.balanceOf(targetUser), 0);
    }
}
