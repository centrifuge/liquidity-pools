// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.18;
pragma abicoder v2;

import {InvestmentManager} from "src/InvestmentManager.sol";
import {PoolManager} from "src/PoolManager.sol";
import {Gateway} from "src/gateway/Gateway.sol";
import {Root} from "src/Root.sol";
import {Escrow} from "src/Escrow.sol";
import {PauseAdmin} from "src/admins/PauseAdmin.sol";
import {DelayedAdmin} from "src/admins/DelayedAdmin.sol";
import {LiquidityPoolFactory, TrancheTokenFactory} from "src/util/Factory.sol";
import {ERC20} from "src/token/ERC20.sol";
import {MemberlistLike, Memberlist} from "src/token/Memberlist.sol";
import {MockHomeLiquidityPools} from "./mock/MockHomeLiquidityPools.sol";
import {MockXcmRouter} from "./mock/MockXcmRouter.sol";
import {Messages} from "src/gateway/Messages.sol";
import "forge-std/Test.sol";

interface EscrowLike_ {
    function approve(address token, address spender, uint256 value) external;
    function rely(address usr) external;
}

contract AdminTest is Test {
    InvestmentManager evmInvestmentManager;
    PoolManager evmPoolManager;
    Root root;
    Gateway gateway;
    MockHomeLiquidityPools centChainLiquidityPools;
    MockXcmRouter mockXcmRouter;
    PauseAdmin pauseAdmin;
    DelayedAdmin delayedAdmin;
    uint256 timelock;

    function setUp() public {
        timelock = 48 hours;
        address escrow_ = address(new Escrow());
        root = new Root(address(escrow_), 48 hours);
        LiquidityPoolFactory liquidityPoolFactory_ = new LiquidityPoolFactory(address(root));
        TrancheTokenFactory trancheTokenFactory_ = new TrancheTokenFactory(address(root));

        evmInvestmentManager = new InvestmentManager(escrow_);
        evmPoolManager = new PoolManager(escrow_, address(liquidityPoolFactory_), address(trancheTokenFactory_));
        liquidityPoolFactory_.rely(address(evmPoolManager));
        trancheTokenFactory_.rely(address(evmPoolManager));

        mockXcmRouter = new MockXcmRouter(address(evmInvestmentManager));

        centChainLiquidityPools = new MockHomeLiquidityPools(address(mockXcmRouter));
        pauseAdmin = new PauseAdmin(address(root));
        delayedAdmin = new DelayedAdmin(address(root));
        pauseAdmin.addPauser(address(this));
        root.rely(address(pauseAdmin));
        root.rely(address(delayedAdmin));

        gateway =
            new Gateway(address(root), address(evmInvestmentManager), address(evmPoolManager), address(mockXcmRouter));
        evmInvestmentManager.file("gateway", address(gateway));
        evmInvestmentManager.file("poolManager", address(evmPoolManager));
        evmPoolManager.file("gateway", address(gateway));
        evmPoolManager.file("investmentManager", address(evmInvestmentManager));
        EscrowLike_(escrow_).rely(address(evmInvestmentManager));
        EscrowLike_(escrow_).rely(address(evmPoolManager));
        mockXcmRouter.file("gateway", address(gateway));
        evmInvestmentManager.rely(address(gateway));
        Escrow(escrow_).rely(address(gateway));
    }

    //------ PauseAdmin tests ------//

    function testPause() public {
        pauseAdmin.pause();
        assertEq(root.paused(), true);

        delayedAdmin.unpause();
        assertEq(root.paused(), false);
    }

    function testPauseAuth(address usr) public {
        vm.assume(usr != address(this));
        vm.expectRevert("PauseAdmin/not-authorized-to-pause");
        vm.prank(usr);
        pauseAdmin.pause();
    }

    function testOutgoingTransferWhilePausedFails(
        string memory tokenName,
        string memory tokenSymbol,
        uint8 decimals,
        uint128 currency,
        address recipient,
        uint128 amount
    ) public {
        vm.assume(decimals > 0);
        vm.assume(decimals <= 18);
        vm.assume(amount > 0);
        vm.assume(currency != 0);
        vm.assume(recipient != address(0));

        ERC20 erc20 = newErc20(tokenName, tokenSymbol, decimals);
        centChainLiquidityPools.addCurrency(currency, address(erc20));

        // First, an outgoing transfer must take place which has funds currency of the currency moved to
        // the escrow account, from which funds are moved from into the recipient on an incoming transfer.
        erc20.approve(address(evmPoolManager), type(uint256).max);
        erc20.mint(address(this), amount);
        pauseAdmin.pause();
        vm.expectRevert("Gateway/paused");
        evmPoolManager.transfer(address(erc20), bytes32(bytes20(recipient)), amount);
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
        vm.assume(decimals > 0);
        vm.assume(decimals <= 18);
        vm.assume(amount > 0);
        vm.assume(currency != 0);
        vm.assume(recipient != address(0));

        ERC20 erc20 = newErc20(tokenName, tokenSymbol, decimals);
        centChainLiquidityPools.addCurrency(currency, address(erc20));

        // First, an outgoing transfer must take place which has funds currency of the currency moved to
        // the escrow account, from which funds are moved from into the recipient on an incoming transfer.
        erc20.approve(address(evmPoolManager), type(uint256).max);
        erc20.mint(address(this), amount);
        evmPoolManager.transfer(address(erc20), bytes32(bytes20(recipient)), amount);
        assertEq(erc20.balanceOf(address(evmPoolManager.escrow())), amount);

        pauseAdmin.pause();
        vm.expectRevert("Gateway/paused");
        centChainLiquidityPools.incomingTransfer(currency, sender, bytes32(bytes20(recipient)), amount);
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
        vm.assume(decimals > 0);
        vm.assume(decimals <= 18);
        vm.assume(amount > 0);
        vm.assume(currency != 0);
        vm.assume(recipient != address(evmInvestmentManager.escrow()));
        vm.assume(recipient != address(0));

        ERC20 erc20 = newErc20(tokenName, tokenSymbol, decimals);
        vm.assume(recipient != address(erc20));
        centChainLiquidityPools.addCurrency(currency, address(erc20));

        // First, an outgoing transfer must take place which has funds currency of the currency moved to
        // the escrow account, from which funds are moved from into the recipient on an incoming transfer.
        erc20.approve(address(evmPoolManager), type(uint256).max);
        erc20.mint(address(this), amount);
        pauseAdmin.pause();
        delayedAdmin.unpause();
        evmPoolManager.transfer(address(erc20), bytes32(bytes20(recipient)), amount);
        assertEq(erc20.balanceOf(address(evmPoolManager.escrow())), amount);

        centChainLiquidityPools.incomingTransfer(currency, sender, bytes32(bytes20(recipient)), amount);
        assertEq(erc20.balanceOf(address(evmPoolManager.escrow())), 0);
        assertEq(erc20.balanceOf(recipient), amount);
    }

    //------ Delayed admin tests ------///
    function testTimelockWorks() public {
        address spell = vm.addr(1);
        delayedAdmin.schedule(spell);
        vm.warp(block.timestamp + timelock + 1 hours);
        root.executeScheduledRely(spell);
        assertEq(root.wards(spell), 1);
    }

    function testTimelockFailsBefore48hours() public {
        address spell = vm.addr(1);
        delayedAdmin.schedule(spell);
        vm.warp(block.timestamp + timelock - 1 hours);
        vm.expectRevert("Root/target-not-ready");
        root.executeScheduledRely(spell);
    }

    function testCancellingScheduleWorks() public {
        address spell = vm.addr(1);
        delayedAdmin.schedule(spell);
        assertEq(root.schedule(spell), block.timestamp + timelock);
        delayedAdmin.cancelRely(spell);
        assertEq(root.schedule(spell), 0);
        vm.warp(block.timestamp + timelock + 1 hours);
        vm.expectRevert("Root/target-not-scheduled");
        root.executeScheduledRely(spell);
    }

    function testUnauthorizedCancelFails() public {
        address spell = vm.addr(1);
        delayedAdmin.schedule(spell);
        vm.expectRevert("Auth/not-authorized");
        vm.prank(spell);
        delayedAdmin.cancelRely(spell);
    }

    //------ helpers ------//

    function newErc20(string memory name, string memory symbol, uint8 decimals) internal returns (ERC20) {
        ERC20 erc20 = new ERC20(decimals);
        erc20.file("name", name);
        erc20.file("symbol", symbol);

        return erc20;
    }
}
