// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.18;

import {TrancheToken} from "src/token/Tranche.sol";
import {MemberlistLike, Memberlist} from "src/token/Memberlist.sol";
import "forge-std/Test.sol";

interface ERC20Like {
    function balanceOf(address) external view returns (uint256);
}

contract TrancheTokenTest is Test {
    TrancheToken token;
    Memberlist memberlist;

    function setUp() public {
        token = new TrancheToken(18);
        token.file("name", "Some Token");
        token.file("symbol", "ST");

        memberlist = new Memberlist();
        token.file("memberlist", address(memberlist));

        memberlist.updateMember(address(this), type(uint256).max);
    }

    // transferFrom
    function testTransferFromTokensToMemberWorks(uint256 amount, address targetUser, uint256 validUntil) public {
        vm.assume(baseAssumptions(validUntil, targetUser));

        memberlist.updateMember(targetUser, validUntil);
        assertEq(memberlist.members(targetUser), validUntil);

        token.mint(address(this), amount);
        token.transferFrom(address(this), targetUser, amount);
        assertEq(token.balanceOf(targetUser), amount);
    }

    function testTransferFromTokensToNonMemberFails(uint256 amount, address targetUser, uint256 validUntil) public {
        vm.assume(baseAssumptions(validUntil, targetUser));

        token.mint(address(this), amount);
        vm.expectRevert(bytes("Memberlist/not-allowed-to-hold-token"));
        token.transferFrom(address(this), targetUser, amount);
        assertEq(token.balanceOf(targetUser), 0);
    }

    function testTransferFromTokensToExpiredMemberFails(uint256 amount, address targetUser) public {
        vm.assume(targetUser != address(0) && targetUser != address(this) && targetUser != address(token));

        memberlist.updateMember(targetUser, block.timestamp);
        assertEq(memberlist.members(targetUser), block.timestamp);

        vm.warp(block.timestamp + 1);

        token.mint(address(this), amount);
        vm.expectRevert(bytes("Memberlist/not-allowed-to-hold-token"));
        token.transferFrom(address(this), targetUser, amount);
        assertEq(token.balanceOf(targetUser), 0);
    }

    // Transfer
    function testTransferTokensToMemberWorks(uint256 amount, address targetUser, uint256 validUntil) public {
        vm.assume(baseAssumptions(validUntil, targetUser));

        memberlist.updateMember(targetUser, validUntil);
        assertEq(memberlist.members(targetUser), validUntil);

        token.mint(address(this), amount);
        token.transfer(targetUser, amount);
        assertEq(token.balanceOf(targetUser), amount);
    }

    function testTransferTokensToNonMemberFails(uint256 amount, address targetUser, uint256 validUntil) public {
        vm.assume(baseAssumptions(validUntil, targetUser));

        token.mint(address(this), amount);
        vm.expectRevert(bytes("Memberlist/not-allowed-to-hold-token"));
        token.transfer(targetUser, amount);
        assertEq(token.balanceOf(targetUser), 0);
    }

    function testTransferTokensToExpiredMemberFails(uint256 amount, address targetUser) public {
        vm.assume(targetUser != address(0) && targetUser != address(this) && targetUser != address(token));

        memberlist.updateMember(targetUser, block.timestamp);
        assertEq(memberlist.members(targetUser), block.timestamp);

        vm.warp(block.timestamp + 1);

        token.mint(address(this), amount);
        vm.expectRevert(bytes("Memberlist/not-allowed-to-hold-token"));
        token.transfer(targetUser, amount);
        assertEq(token.balanceOf(targetUser), 0);
    }

    // Mint
    function testMintTokensToMemberWorks(uint256 amount, address targetUser, uint256 validUntil) public {
        vm.assume(baseAssumptions(validUntil, targetUser));

        memberlist.updateMember(targetUser, validUntil);
        assertEq(memberlist.members(targetUser), validUntil);

        token.mint(targetUser, amount);
        assertEq(token.balanceOf(targetUser), amount);
    }

    function testMintTokensToNonMemberFails(uint256 amount, address targetUser, uint256 validUntil) public {
        vm.assume(baseAssumptions(validUntil, targetUser));

        vm.expectRevert(bytes("Memberlist/not-allowed-to-hold-token"));
        token.mint(targetUser, amount);
        assertEq(token.balanceOf(targetUser), 0);
    }

    function testMintTokensToExpiredMemberFails(uint256 amount, address targetUser) public {
        vm.assume(targetUser != address(0) && targetUser != address(this) && targetUser != address(token));

        memberlist.updateMember(targetUser, block.timestamp);
        assertEq(memberlist.members(targetUser), block.timestamp);

        vm.warp(block.timestamp + 1);

        vm.expectRevert(bytes("Memberlist/not-allowed-to-hold-token"));
        token.mint(targetUser, amount);
        assertEq(token.balanceOf(targetUser), 0);
    }

    function baseAssumptions(uint256 validUntil, address targetUser) internal view returns (bool) {
        return validUntil > block.timestamp && targetUser != address(0) && targetUser != address(this)
            && targetUser != address(token);
    }
}
