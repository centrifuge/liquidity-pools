// // SPDX-License-Identifier: AGPL-3.0-only
// pragma solidity ^0.8.18;
// pragma abicoder v2;

// import {InvestmentManager} from "src/InvestmentManager.sol";
// import {Gateway} from "src/Gateway.sol";
// import {Escrow} from "src/Escrow.sol";
// import {PauseAdmin} from "src/admin/PauseAdmin.sol";
// import {DelayedAdmin} from "src/admin/DelayedAdmin.sol";
// import {LiquidityPoolFactory, MemberlistFactory} from "src/liquidityPool/Factory.sol";
// import {RestrictedTokenLike} from "src/token/Restricted.sol";
// import {ERC20} from "src/token/ERC20.sol";
// import {MemberlistLike, Memberlist} from "src/token/Memberlist.sol";
// import {MockHomeLiquidityPools} from "./mock/MockHomeLiquidityPools.sol";
// import {MockXcmRouter} from "./mock/MockXcmRouter.sol";
// import {Messages} from "../src/Messages.sol";
// import "forge-std/Test.sol";

// interface EscrowLike_ {
//     function approve(address token, address spender, uint256 value) external;
//     function rely(address usr) external;
// }

// contract AdminTest is Test {
//     InvestmentManager investmentManager;
//     Gateway gateway;
//     MockHomeLiquidityPools centChainLiquidityPools;
//     MockXcmRouter mockXcmRouter;
//     PauseAdmin pauseAdmin;
//     DelayedAdmin delayedAdmin;
//     uint256 shortWait;
//     uint256 longWait;
//     uint256 gracePeriod;

//     function setUp() public {
//         shortWait = 24 hours;
//         longWait = 48 hours;
//         gracePeriod = 48 hours;
//         address escrow_ = address(new Escrow());
//         address liquidityPoolFactory_ = address(new LiquidityPoolFactory());
//         address memberlistFactory_ = address(new MemberlistFactory());

//         investmentManager = new InvestmentManager(escrow_, liquidityPoolFactory_, memberlistFactory_);

//         mockXcmRouter = new MockXcmRouter(address(investmentManager));

//         centChainLiquidityPools = new MockHomeLiquidityPools(address(mockXcmRouter));
//         pauseAdmin = new PauseAdmin();
//         delayedAdmin = new DelayedAdmin();
//         gateway = new Gateway(address(investmentManager), address(mockXcmRouter), shortWait, longWait, gracePeriod);
//         gateway.rely(address(pauseAdmin));
//         gateway.rely(address(delayedAdmin));
//         investmentManager.file("gateway", address(gateway));
//         pauseAdmin.file("gateway", address(gateway));
//         delayedAdmin.file("gateway", address(gateway));
//         EscrowLike_(escrow_).rely(address(investmentManager));
//         mockXcmRouter.file("gateway", address(gateway));

//         investmentManager.rely(address(gateway));
//         EscrowLike_(escrow_).rely(address(gateway));
//     }

//     //------ PauseAdmin tests ------//

//     function testPause() public {
//         pauseAdmin.pause();
//         assertEq(gateway.paused(), true);

//         pauseAdmin.unpause();
//         assertEq(gateway.paused(), false);
//     }

//     function testPauseAuth(address usr) public {
//         vm.assume(usr != address(this));
//         vm.expectRevert("not-authorized");
//         vm.prank(usr);
//         pauseAdmin.pause();
//     }

//     function testOutgoingTransferWhilePausedFails(
//         string memory tokenName,
//         string memory tokenSymbol,
//         uint8 decimals,
//         uint128 currency,
//         bytes32 sender,
//         address recipient,
//         uint128 amount
//     ) public {
//         vm.assume(decimals > 0);
//         vm.assume(amount > 0);
//         vm.assume(currency != 0);
//         vm.assume(recipient != address(0));

//         ERC20 erc20 = newErc20(tokenName, tokenSymbol, decimals);
//         centChainLiquidityPools.addCurrency(currency, address(erc20));

//         // First, an outgoing transfer must take place which has funds currency of the currency moved to
//         // the escrow account, from which funds are moved from into the recipient on an incoming transfer.
//         erc20.approve(address(investmentManager), type(uint256).max);
//         erc20.mint(address(this), amount);
//         pauseAdmin.pause();
//         vm.expectRevert("Gateway/paused");
//         investmentManager.transfer(address(erc20), bytes32(bytes20(recipient)), amount);
//     }

//     function testIncomingTransferWhilePausedFails(
//         string memory tokenName,
//         string memory tokenSymbol,
//         uint8 decimals,
//         uint128 currency,
//         bytes32 sender,
//         address recipient,
//         uint128 amount
//     ) public {
//         vm.assume(decimals > 0);
//         vm.assume(amount > 0);
//         vm.assume(currency != 0);
//         vm.assume(recipient != address(0));

//         ERC20 erc20 = newErc20(tokenName, tokenSymbol, decimals);
//         centChainLiquidityPools.addCurrency(currency, address(erc20));

//         // First, an outgoing transfer must take place which has funds currency of the currency moved to
//         // the escrow account, from which funds are moved from into the recipient on an incoming transfer.
//         erc20.approve(address(investmentManager), type(uint256).max);
//         erc20.mint(address(this), amount);
//         investmentManager.transfer(address(erc20), bytes32(bytes20(recipient)), amount);
//         assertEq(erc20.balanceOf(address(investmentManager.escrow())), amount);

//         pauseAdmin.pause();
//         vm.expectRevert("Gateway/paused");
//         centChainLiquidityPools.incomingTransfer(currency, sender, bytes32(bytes20(recipient)), amount);
//     }

//     function testUnpausingResumesFunctionality(
//         string memory tokenName,
//         string memory tokenSymbol,
//         uint8 decimals,
//         uint128 currency,
//         bytes32 sender,
//         address recipient,
//         uint128 amount
//     ) public {
//         vm.assume(decimals > 0);
//         vm.assume(amount > 0);
//         vm.assume(currency != 0);
//         vm.assume(recipient != address(investmentManager.escrow()));
//         vm.assume(recipient != address(0));

//         ERC20 erc20 = newErc20(tokenName, tokenSymbol, decimals);
//         vm.assume(recipient != address(erc20));
//         centChainLiquidityPools.addCurrency(currency, address(erc20));

//         // First, an outgoing transfer must take place which has funds currency of the currency moved to
//         // the escrow account, from which funds are moved from into the recipient on an incoming transfer.
//         erc20.approve(address(investmentManager), type(uint256).max);
//         erc20.mint(address(this), amount);
//         pauseAdmin.pause();
//         pauseAdmin.unpause();
//         investmentManager.transfer(address(erc20), bytes32(bytes20(recipient)), amount);
//         assertEq(erc20.balanceOf(address(investmentManager.escrow())), amount);

//         centChainLiquidityPools.incomingTransfer(currency, sender, bytes32(bytes20(recipient)), amount);
//         assertEq(erc20.balanceOf(address(investmentManager.escrow())), 0);
//         assertEq(erc20.balanceOf(recipient), amount);
//     }

//     function testPauseAdminCanCancelScheduledRely() public {
//         address spell = vm.addr(1);
//         delayedAdmin.schedule(spell);
//         pauseAdmin.cancelSchedule(spell);
//         assertEq(gateway.relySchedule(spell), 0);
//     }

//     //------ Delayed Long admin tests ------///

//     function testLongRelyWorks() public {
//         address spell = vm.addr(1);
//         delayedAdmin.schedule(spell);
//         vm.warp(block.timestamp + longWait + 1 hours);
//         gateway.executeScheduledRely(spell);
//         assertEq(gateway.wards(spell), 1);
//     }

//     function testLongRelyFailsBefore48hours() public {
//         address spell = vm.addr(1);
//         delayedAdmin.schedule(spell);
//         vm.warp(block.timestamp + longWait - 1 hours);
//         vm.expectRevert("Gateway/user-not-ready");
//         gateway.executeScheduledRely(spell);
//     }

//     function testLongRelyFailsAfterGracePeriod() public {
//         address spell = vm.addr(1);
//         delayedAdmin.schedule(spell);
//         vm.warp(block.timestamp + longWait + gateway.gracePeriod());
//         vm.expectRevert("Gateway/user-too-old");
//         gateway.executeScheduledRely(spell);
//     }

//     function testCancellingScheduleWorks() public {
//         address spell = vm.addr(1);
//         delayedAdmin.schedule(spell);
//         assertEq(gateway.relySchedule(spell), block.timestamp + longWait);
//         delayedAdmin.cancelSchedule(spell);
//         assertEq(gateway.relySchedule(spell), 0);
//         vm.warp(block.timestamp + longWait + 1 hours);
//         vm.expectRevert("Gateway/user-not-scheduled");
//         gateway.executeScheduledRely(spell);
//     }

//     function testUnauthorizedCancelFails() public {
//         address spell = vm.addr(1);
//         delayedAdmin.schedule(spell);
//         vm.expectRevert("not-authorized");
//         vm.prank(spell);
//         delayedAdmin.cancelSchedule(spell);
//     }

//     //------ delayed Short admin tests ------//

//     function testShortRelyWorks() public {
//         address spell = vm.addr(1);
//         centChainLiquidityPools.incomingScheduleUpgrade(spell);
//         vm.warp(block.timestamp + shortWait + 1 hours);
//         gateway.executeScheduledRely(spell);
//         assertEq(gateway.wards(spell), 1);
//     }

//     function testShortRelyFailsBefore24hours() public {
//         address spell = vm.addr(1);
//         centChainLiquidityPools.incomingScheduleUpgrade(spell);
//         vm.warp(block.timestamp + shortWait - 1 hours);
//         vm.expectRevert("Gateway/user--not-ready");
//         gateway.executeScheduledRely(spell);
//     }

//     function testShortRelyFailsAfterGracePeriod() public {
//         address spell = vm.addr(1);
//         centChainLiquidityPools.incomingScheduleUpgrade(spell);
//         vm.warp(block.timestamp + shortWait + gateway.gracePeriod());
//         vm.expectRevert("Gateway/user-too-old");
//         gateway.executeScheduledRely(spell);
//     }

//     //------ helpers ------//

//     function newErc20(string memory name, string memory symbol, uint8 decimals) internal returns (ERC20) {
//         ERC20 erc20 = new ERC20(decimals);
//         erc20.file("name", name);
//         erc20.file("symbol", symbol);

//         return erc20;
//     }
// }
