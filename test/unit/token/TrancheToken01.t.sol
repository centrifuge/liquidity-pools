// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import {TrancheToken01} from "src/token/TrancheToken01.sol";
import "forge-std/Test.sol";

interface ERC20Like {
    function balanceOf(address) external view returns (uint256);
}

contract TrancheToken01Test is Test {
    uint256 constant MAX_TRANCHE_TOKEN_BALANCE = 2 ^ 255 - 1; // ignoring high bit used for freezes

    TrancheToken01 token;

    address self;
    address escrow = makeAddr("escrow");
    address targetUser = makeAddr("targetUser");
    address randomUser = makeAddr("random");
    uint64 validUntil = uint64(block.timestamp + 7 days);

    function setUp() public {
        self = address(this);
        token = new TrancheToken01(18, escrow);
        token.file("name", "Some Token");
        token.file("symbol", "ST");
    }

    // --- Admnistration ---

    function testFile(address asset, address vault) public {
        token.updateVault(asset, vault);
        assertEq(address(token.vault(asset)), vault);

        // remove self from wards
        token.deny(self);

        vm.expectRevert(bytes("Auth/not-authorized"));
        token.updateVault(asset, vault);
    }

    // --- RestrictionManager ---
    // transferFrom
    function testTransferFrom(uint256 amount) public {
        amount = bound(amount, 0, MAX_TRANCHE_TOKEN_BALANCE / 2);

        token.updateMember(self, uint64(validUntil));
        token.mint(self, amount * 2);

        vm.expectRevert(bytes("TrancheToken01/restrictions-failed"));
        token.transferFrom(self, targetUser, amount);
        assertEq(token.balanceOf(targetUser), 0);

        token.updateMember(targetUser, uint64(validUntil));
        (uint64 actualValidUntil) = token.restrictions(targetUser);
        assertEq(actualValidUntil, validUntil);

        token.freeze(self);
        vm.expectRevert(bytes("TrancheToken01/restrictions-failed"));
        token.transferFrom(self, targetUser, amount);
        assertEq(token.balanceOf(targetUser), 0);

        token.unfreeze(self);
        token.freeze(targetUser);
        vm.expectRevert(bytes("TrancheToken01/restrictions-failed"));
        token.transferFrom(self, targetUser, amount);
        assertEq(token.balanceOf(targetUser), 0);

        token.unfreeze(targetUser);
        token.transferFrom(self, targetUser, amount);
        assertEq(token.balanceOf(targetUser), amount);

        vm.warp(validUntil + 1);
        token.setInvalidMember(targetUser);
        vm.expectRevert(bytes("TrancheToken01/restrictions-failed"));
        token.transferFrom(self, targetUser, amount);
    }

    function testTransferFromTokensWithApproval(uint256 amount) public {
        amount = bound(amount, 1, MAX_TRANCHE_TOKEN_BALANCE);

        address sender = makeAddr("sender");
        token.updateMember(sender, uint64(validUntil));
        token.mint(sender, amount);

        token.updateMember(targetUser, uint64(validUntil));

        vm.expectRevert(bytes("ERC20/insufficient-allowance"));
        token.transferFrom(sender, targetUser, amount);

        vm.prank(sender);
        token.approve(self, amount);
        token.transferFrom(sender, targetUser, amount);
        assertEq(token.balanceOf(targetUser), amount);
        assertEq(token.balanceOf(sender), 0);
    }

    // transfer
    function testTransfer(uint256 amount) public {
        amount = bound(amount, 0, MAX_TRANCHE_TOKEN_BALANCE / 2);

        token.updateMember(self, uint64(validUntil));
        token.mint(self, amount * 2);

        vm.expectRevert(bytes("TrancheToken01/restrictions-failed"));
        token.transfer(targetUser, amount);
        assertEq(token.balanceOf(targetUser), 0);

        token.updateMember(targetUser, uint64(validUntil));
        (uint64 actualValidUntil) = token.restrictions(targetUser);
        assertEq(actualValidUntil, validUntil);

        token.freeze(self);
        vm.expectRevert(bytes("TrancheToken01/restrictions-failed"));
        token.transfer(targetUser, amount);
        assertEq(token.balanceOf(targetUser), 0);

        token.unfreeze(self);
        token.transfer(targetUser, amount);
        assertEq(token.balanceOf(targetUser), amount);

        vm.warp(validUntil + 1);
        token.setInvalidMember(targetUser);
        vm.expectRevert(bytes("TrancheToken01/restrictions-failed"));
        token.transfer(targetUser, amount);
    }

    // auth transfer
    function testAuthTransferFrom(uint256 amount) public {
        amount = bound(amount, 0, MAX_TRANCHE_TOKEN_BALANCE);

        address sourceUser = makeAddr("sourceUser");
        token.updateMember(sourceUser, uint64(validUntil));
        token.mint(sourceUser, amount);

        vm.prank(address(2));
        vm.expectRevert(bytes("Auth/not-authorized"));
        token.authTransferFrom(sourceUser, sourceUser, self, amount);
        assertEq(token.balanceOf(sourceUser), amount);
        assertEq(token.balanceOf(self), 0);

        token.authTransferFrom(sourceUser, sourceUser, self, amount);
        assertEq(token.balanceOf(sourceUser), 0);
        assertEq(token.balanceOf(self), amount);
    }

    // mint
    function testMintTokensToMemberWorks(uint256 amount) public {
        amount = bound(amount, 0, MAX_TRANCHE_TOKEN_BALANCE / 2);

        // mint fails -> self not a member
        vm.expectRevert(bytes("TrancheToken01/restrictions-failed"));
        token.mint(targetUser, amount);

        token.updateMember(targetUser, uint64(validUntil));
        (uint64 actualValidUntil) = token.restrictions(targetUser);
        assertEq(actualValidUntil, validUntil);

        token.mint(targetUser, amount);
        assertEq(token.balanceOf(targetUser), amount);

        vm.warp(validUntil + 1);

        token.setInvalidMember(targetUser);
        vm.expectRevert(bytes("TrancheToken01/restrictions-failed"));
        token.mint(targetUser, amount);
    }

    function testAuthTransferFrom(address to, uint256 amount) public {
        if (to == address(0) || to == address(token)) return;

        address from = address(0xABCD);

        token.mint(from, amount);

        assertTrue(token.authTransferFrom(from, from, to, amount));
        assertEq(token.totalSupply(), amount);

        if (from == to) {
            assertEq(token.balanceOf(from), amount);
        } else {
            assertEq(token.balanceOf(from), 0);
            assertEq(token.balanceOf(to), amount);
        }
    }
}
