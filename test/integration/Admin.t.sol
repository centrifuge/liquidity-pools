// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import "test/BaseTest.sol";

contract AdminTest is BaseTest {
    function setUp() public override {
        super.setUp();
    }

    function testDeployment() public {
        // values set correctly
        assertEq(address(root.escrow()), address(escrow));
        assertEq(root.paused(), false);

        // permissions set correctly
        assertEq(root.wards(address(guardian)), 1);
    }

    //------ PauseAdmin tests ------//
    function testUnauthorizedPauseFails() public {
        guardianSafe.removeOwner(address(this));
        vm.expectRevert("Guardian/not-an-owner-of-the-authorized-safe");
        guardian.pause();
    }

    function testPauseWorks() public {
        guardian.pause();
        assertEq(root.paused(), true);
    }

    function testUnpauseWorks() public {
        vm.prank(address(guardianSafe));
        guardian.unpause();
        assertEq(root.paused(), false);
    }

    function testUnauthorizedUnpauseFails() public {
        vm.expectRevert("Guardian/not-an-authorized-safe");
        guardian.unpause();
    }

    function testOutgoingTransferWhilePausedFails(
        string memory tokenName,
        string memory tokenSymbol,
        uint8 decimals,
        uint128 currency,
        address recipient,
        uint128 amount
    ) public {
        decimals = uint8(bound(decimals, 1, 18));
        vm.assume(amount > 0);
        vm.assume(currency != 0);
        vm.assume(recipient != address(0));

        ERC20 erc20 = _newErc20(tokenName, tokenSymbol, decimals);
        centrifugeChain.addCurrency(currency, address(erc20));

        // First, an outgoing transfer must take place which has funds currency of the currency moved to
        // the escrow account, from which funds are moved from into the recipient on an incoming transfer.
        erc20.approve(address(poolManager), type(uint256).max);
        erc20.mint(address(this), amount);
        guardian.pause();
        vm.expectRevert("Gateway/paused");
        poolManager.transfer(address(erc20), bytes32(bytes20(recipient)), amount);
    }

    function testIncomingTransferWhilePausedFails(
        string memory tokenName,
        string memory tokenSymbol,
        uint8 decimals,
        uint128 currency,
        bytes32 sender,
        address recipient,
        uint128 amount
    ) public {
        decimals = uint8(bound(decimals, 1, 18));
        vm.assume(amount > 0);
        vm.assume(currency != 0);
        vm.assume(recipient != address(0));

        ERC20 erc20 = _newErc20(tokenName, tokenSymbol, decimals);
        centrifugeChain.addCurrency(currency, address(erc20));

        // First, an outgoing transfer must take place which has funds currency of the currency moved to
        // the escrow account, from which funds are moved from into the recipient on an incoming transfer.
        erc20.approve(address(poolManager), type(uint256).max);
        erc20.mint(address(this), amount);
        poolManager.transfer(address(erc20), bytes32(bytes20(recipient)), amount);
        assertEq(erc20.balanceOf(address(poolManager.escrow())), amount);

        guardian.pause();
        vm.expectRevert("Gateway/paused");
        centrifugeChain.incomingTransfer(currency, sender, bytes32(bytes20(recipient)), amount);
    }

    function testUnpausingResumesFunctionality(
        string memory tokenName,
        string memory tokenSymbol,
        uint8 decimals,
        uint128 currency,
        bytes32 sender,
        address recipient,
        uint128 amount
    ) public {
        decimals = uint8(bound(decimals, 1, 18));
        vm.assume(amount > 0);
        vm.assume(currency != 0);
        vm.assume(recipient != address(investmentManager.escrow()));
        vm.assume(recipient != address(0));

        ERC20 erc20 = _newErc20(tokenName, tokenSymbol, decimals);
        vm.assume(recipient != address(erc20));
        centrifugeChain.addCurrency(currency, address(erc20));

        // First, an outgoing transfer must take place which has funds currency of the currency moved to
        // the escrow account, from which funds are moved from into the recipient on an incoming transfer.
        erc20.approve(address(poolManager), type(uint256).max);
        erc20.mint(address(this), amount);
        guardian.pause();
        vm.prank(address(guardianSafe));
        guardian.unpause();
        poolManager.transfer(address(erc20), bytes32(bytes20(recipient)), amount);
        assertEq(erc20.balanceOf(address(poolManager.escrow())), amount);

        centrifugeChain.incomingTransfer(currency, sender, bytes32(bytes20(recipient)), amount);
        assertEq(erc20.balanceOf(address(poolManager.escrow())), 0);
        assertEq(erc20.balanceOf(recipient), amount);
    }

    //------ Delayed admin tests ------///
    function testGuardianPause() public {
        guardian.pause();
        assertEq(root.paused(), true);
    }

    function testGuardianUnpause() public {
        guardian.pause();
        vm.prank(address(guardianSafe));
        guardian.unpause();
        assertEq(root.paused(), false);
    }

    function testGuardianPauseAuth(address user) public {
        vm.assume(user != address(this));
        vm.expectRevert("Guardian/not-an-owner-of-the-authorized-safe");
        vm.prank(user);
        guardian.pause();
    }

    function testTimelockWorks() public {
        address spell = vm.addr(1);
        vm.prank(address(guardianSafe));
        guardian.scheduleRely(spell);
        vm.warp(block.timestamp + delay + 1 hours);
        root.executeScheduledRely(spell);
        assertEq(root.wards(spell), 1);
    }

    function testTimelockFailsBefore48hours() public {
        address spell = vm.addr(1);
        vm.prank(address(guardianSafe));
        guardian.scheduleRely(spell);
        vm.warp(block.timestamp + delay - 1 hours);
        vm.expectRevert("Root/target-not-ready");
        root.executeScheduledRely(spell);
    }

    function testCancellingScheduleBeforeRelyFails() public {
        address spell = vm.addr(1);
        vm.expectRevert("Root/target-not-scheduled");
        root.cancelRely(spell);
    }

    function testCancellingScheduleWorks() public {
        address spell = vm.addr(1);
        vm.prank(address(guardianSafe));
        guardian.scheduleRely(spell);
        assertEq(root.schedule(spell), block.timestamp + delay);
        vm.prank(address(guardianSafe));
        guardian.cancelRely(spell);
        assertEq(root.schedule(spell), 0);
        vm.warp(block.timestamp + delay + 1 hours);
        vm.expectRevert("Root/target-not-scheduled");
        root.executeScheduledRely(spell);
    }

    function testUnauthorizedCancelFails() public {
        address spell = vm.addr(1);
        vm.prank(address(guardianSafe));
        guardian.scheduleRely(spell);
        address badActor = vm.addr(0xBAD);
        vm.expectRevert("Guardian/not-an-authorized-safe");
        vm.prank(badActor);
        guardian.cancelRely(spell);
    }

    function testAddedSafeOwnerCanPause() public {
        address newOwner = vm.addr(0xABCDE);
        guardianSafe.addOwner(newOwner);
        vm.prank(newOwner);
        guardian.pause();
        assertEq(root.paused(), true);
    }

    function testRemovedOwnerCannotPause() public {
        guardianSafe.removeOwner(address(this));
        assertEq(guardianSafe.isOwner(address(this)), false);
        vm.expectRevert("Guardian/not-an-owner-of-the-authorized-safe");
        vm.prank(address(this));
        guardian.pause();
    }

    function testIncomingScheduleUpgradeMessage() public {
        address spell = vm.addr(1);
        centrifugeChain.incomingScheduleUpgrade(spell);
        vm.warp(block.timestamp + delay + 1 hours);
        root.executeScheduledRely(spell);
        assertEq(root.wards(spell), 1);
    }

    function testIncomingCancelUpgradeMessage() public {
        address spell = vm.addr(1);
        centrifugeChain.incomingScheduleUpgrade(spell);
        assertEq(root.schedule(spell), block.timestamp + delay);
        centrifugeChain.incomingCancelUpgrade(spell);
        assertEq(root.schedule(spell), 0);
        vm.warp(block.timestamp + delay + 1 hours);
        vm.expectRevert("Root/target-not-scheduled");
        root.executeScheduledRely(spell);
    }

    //------ Updating delay tests ------///
    function testUpdatingDelayWorks() public {
        vm.prank(address(guardianSafe));
        guardian.scheduleRely(address(this));
        vm.warp(block.timestamp + delay + 1 hours);
        root.executeScheduledRely(address(this));
    }

    function testUpdatingDelayWithLargeValueFails() public {
        vm.expectRevert("Root/delay-too-long");
        root.file("delay", 5 weeks);
    }

    function testUpdatingDelayAndExecutingBeforeNewDelayFails() public {
        root.file("delay", 2 hours);
        vm.prank(address(guardianSafe));
        guardian.scheduleRely(address(this));
        vm.warp(block.timestamp + 1 hours);
        vm.expectRevert("Root/target-not-ready");
        root.executeScheduledRely(address(this));
    }

    function testInvalidFile() public {
        vm.expectRevert("Root/file-unrecognized-param");
        root.file("not-delay", 1);
    }

    //------ rely/denyContract tests ------///
    function testRelyDenyContract() public {
        vm.prank(address(guardianSafe));
        guardian.scheduleRely(address(this));
        vm.warp(block.timestamp + delay + 1 hours);
        root.executeScheduledRely(address(this));

        assertEq(investmentManager.wards(address(this)), 1);
        root.denyContract(address(investmentManager), address(this));
        assertEq(investmentManager.wards(address(this)), 0);

        root.relyContract(address(investmentManager), address(this));
        assertEq(investmentManager.wards(address(this)), 1);
    }
}