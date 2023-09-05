// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import {TrancheToken} from "src/token/Tranche.sol";
import {MemberlistLike, Memberlist} from "src/token/Memberlist.sol";
import "forge-std/Test.sol";

interface ERC20Like {
    function balanceOf(address) external view returns (uint256);
}

contract TrancheTokenTest is Test {
    TrancheToken token;
    Memberlist memberlist;

    address self;

    function setUp() public {
        self = address(this);
        token = new TrancheToken(18);
        token.file("name", "Some Token");
        token.file("symbol", "ST");

        memberlist = new Memberlist();
        token.file("memberlist", address(memberlist));

        memberlist.updateMember(address(this), type(uint256).max);
    }

    // --- Admnistration ---

    function testFile() public {
        // fail: unrecognized param
        vm.expectRevert(bytes("TrancheToken/file-unrecognized-param"));
        token.file("random", self);

        // success
        token.file("memberlist", self);
        assertEq(address(token.memberlist()), self);

        // remove self from wards
        token.deny(self);
        // auth fail
        vm.expectRevert(bytes("Auth/not-authorized"));
        token.file("memberlist", self);
    }

    // --- TrustedForwarder ---
    function testAddLiquidityPool() public {
        assert(!token.isTrustedForwarder(self));

        //success
        token.addLiquidityPool(self);
        assert(token.isTrustedForwarder(self));

        // remove self from wards
        token.deny(self);
        // auth fail
        vm.expectRevert(bytes("Auth/not-authorized"));
        token.addLiquidityPool(self);
    }

    function testRemoveLiquidityPool() public {
        token.addLiquidityPool(self);
        assert(token.isTrustedForwarder(self));

        // success
        token.removeLiquidityPool(self);
        assert(!token.isTrustedForwarder(self));

        // remove self from wards
        token.deny(self);
        // auth fail
        vm.expectRevert(bytes("Auth/not-authorized"));
        token.removeLiquidityPool(self);
    }

    function testCheckTrustedForderWorks(uint256 validUntil, uint256 amount, address random) public {
        vm.assume(validUntil > block.timestamp);
        vm.assume(amount > 0);

        assert(!token.isTrustedForwarder(self));
        // make self trusted firwarder
        token.addLiquidityPool(self);
        assert(token.isTrustedForwarder(self));
        // add self to memberlist
        memberlist.updateMember(self, validUntil);
        memberlist.updateMember(random, validUntil);

        bool success;
        // test auth works with trustedForwarder
        // fail -> random not ward
        (success,) = address(token).call(
            abi.encodeWithSelector(bytes4(keccak256(bytes("mint(address,uint256)"))), self, amount, random)
        );
        assert(!success);
        assertEq(token.balanceOf(self), 0);

        // success -> self is ward
        (success,) = address(token).call(
            abi.encodeWithSelector(bytes4(keccak256(bytes("mint(address,uint256)"))), self, amount, self)
        );
        assert(success);
        assertEq(token.balanceOf(self), amount);

        // test non auth function works with trusted forwarder
        // fail -> random has no balance
        (success,) = address(token).call(
            abi.encodeWithSelector(bytes4(keccak256(bytes("transfer(address,uint256)"))), self, amount, random)
        );

        assert(!success);
        assertEq(token.balanceOf(self), amount);

        // success -> self has enough balance to transfer
        (success,) = address(token).call(
            abi.encodeWithSelector(bytes4(keccak256(bytes("transfer(address,uint256)"))), random, amount, self)
        );

        assert(success);
        assertEq(token.balanceOf(self), 0);
        assertEq(token.balanceOf(random), amount);
    }

    // --- Memberlist ---
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
