// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.18;
pragma abicoder v2;

import {CentrifugeConnector} from "src/Connector.sol";
import {ConnectorGateway} from "src/routers/Gateway.sol";
import {ConnectorEscrow} from "src/Escrow.sol";
import {ConnectorPauseAdmin} from "src/PauseAdmin.sol";
import {ConnectorDelayedAdmin} from "src/DelayedAdmin.sol";
import {TrancheTokenFactory, MemberlistFactory} from "src/token/factory.sol";
import {RestrictedTokenLike} from "src/token/restricted.sol";
import {ERC20} from "src/token/erc20.sol";
import {MemberlistLike, Memberlist} from "src/token/memberlist.sol";
import {MockHomeConnector} from "./mock/MockHomeConnector.sol";
import {MockXcmRouter} from "./mock/MockXcmRouter.sol";
import {ConnectorMessages} from "../src/Messages.sol";
import "forge-std/Test.sol";

interface EscrowLike_ {
    function approve(address token, address spender, uint256 value) external;
    function rely(address usr) external;
}

contract AdminTest is Test {
    CentrifugeConnector connector;
    ConnectorGateway gateway;
    MockHomeConnector centChainConnector;
    MockXcmRouter mockXcmRouter;
    ConnectorPauseAdmin pauseAdmin;
    ConnectorDelayedAdmin delayedAdmin;

    function setUp() public {
        address escrow_ = address(new ConnectorEscrow());
        address tokenFactory_ = address(new TrancheTokenFactory());
        address memberlistFactory_ = address(new MemberlistFactory());

        connector = new CentrifugeConnector(escrow_, tokenFactory_, memberlistFactory_);

        mockXcmRouter = new MockXcmRouter(address(connector));

        centChainConnector = new MockHomeConnector(address(mockXcmRouter));
        pauseAdmin = new ConnectorPauseAdmin();
        delayedAdmin = new ConnectorDelayedAdmin();
        gateway =
            new ConnectorGateway(address(connector), address(mockXcmRouter), address(pauseAdmin), address(delayedAdmin));
        connector.file("gateway", address(gateway));
        pauseAdmin.file("gateway", address(gateway));
        delayedAdmin.file("gateway", address(gateway));
        EscrowLike_(escrow_).rely(address(connector));
        mockXcmRouter.file("gateway", address(gateway));

        connector.rely(address(gateway));
        EscrowLike_(escrow_).rely(address(gateway));
    }

    //------ PauseAdmin tests ------//

    function testPause() public {
        pauseAdmin.pause();
        assertEq(gateway.paused(), true);

        pauseAdmin.unpause();
        assertEq(gateway.paused(), false);
    }

    function testPauseAuth(address usr) public {
        vm.assume(usr != address(this));
        vm.expectRevert("ConnectorAdmin/not-authorized");
        vm.prank(usr);
        pauseAdmin.pause();
    }

    function testOutgoingTransferWhilePausedFails(
        string memory tokenName,
        string memory tokenSymbol,
        uint8 decimals,
        uint128 currency,
        bytes32 sender,
        address recipient,
        uint128 amount
    ) public {
        vm.assume(decimals > 0);
        vm.assume(amount > 0);
        vm.assume(currency != 0);
        vm.assume(recipient != address(0));

        ERC20 erc20 = newErc20(tokenName, tokenSymbol, decimals);
        centChainConnector.addCurrency(currency, address(erc20));

        // First, an outgoing transfer must take place which has funds currency of the currency moved to
        // the escrow account, from which funds are moved from into the recipient on an incoming transfer.
        erc20.approve(address(connector), type(uint256).max);
        erc20.mint(address(this), amount);
        pauseAdmin.pause();
        vm.expectRevert("ConnectorGateway/paused");
        connector.transfer(address(erc20), bytes32(bytes20(recipient)), amount);
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
        vm.assume(amount > 0);
        vm.assume(currency != 0);
        vm.assume(recipient != address(0));

        ERC20 erc20 = newErc20(tokenName, tokenSymbol, decimals);
        centChainConnector.addCurrency(currency, address(erc20));

        // First, an outgoing transfer must take place which has funds currency of the currency moved to
        // the escrow account, from which funds are moved from into the recipient on an incoming transfer.
        erc20.approve(address(connector), type(uint256).max);
        erc20.mint(address(this), amount);
        connector.transfer(address(erc20), bytes32(bytes20(recipient)), amount);
        assertEq(erc20.balanceOf(address(connector.escrow())), amount);

        pauseAdmin.pause();
        vm.expectRevert("ConnectorGateway/paused");
        centChainConnector.incomingTransfer(currency, sender, bytes32(bytes20(recipient)), amount);
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
        vm.assume(amount > 0);
        vm.assume(currency != 0);
        vm.assume(recipient != address(0));

        ERC20 erc20 = newErc20(tokenName, tokenSymbol, decimals);
        centChainConnector.addCurrency(currency, address(erc20));

        // First, an outgoing transfer must take place which has funds currency of the currency moved to
        // the escrow account, from which funds are moved from into the recipient on an incoming transfer.
        erc20.approve(address(connector), type(uint256).max);
        erc20.mint(address(this), amount);
        pauseAdmin.pause();
        pauseAdmin.unpause();
        connector.transfer(address(erc20), bytes32(bytes20(recipient)), amount);
        assertEq(erc20.balanceOf(address(connector.escrow())), amount);

        centChainConnector.incomingTransfer(currency, sender, bytes32(bytes20(recipient)), amount);
        assertEq(erc20.balanceOf(address(connector.escrow())), 0);
        assertEq(erc20.balanceOf(recipient), amount);
    }

    function testPauseAdminCanCancelScheduledRely() public {
        address spell = vm.addr(1);
        delayedAdmin.schedule(spell);
        pauseAdmin.cancelSchedule(spell);
        assertEq(gateway.relySchedule(spell), 0);
    }

    //------ Delayed 48hr admin tests ------///

    function test48hrRelyWorks() public {
        address spell = vm.addr(1);
        delayedAdmin.schedule(spell);
        vm.warp(block.timestamp + 49 hours);
        gateway.relySpell(spell);
        assertEq(gateway.wards(spell), 1);
    }

    function test48hrRelyFailsBefore48hours() public {
        address spell = vm.addr(1);
        delayedAdmin.schedule(spell);
        vm.warp(block.timestamp + 44 hours);
        vm.expectRevert("ConnectorGateway/spell-not-ready");
        gateway.relySpell(spell);
    }

    function test48hrRelyFailsAfterGracePeriod() public {
        address spell = vm.addr(1);
        delayedAdmin.schedule(spell);
        vm.warp(block.timestamp + 48 hours + gateway.GRACE_PERIOD());
        vm.expectRevert("ConnectorGateway/spell-too-old");
        gateway.relySpell(spell);
    }

    function testCancellingScheduleWorks() public {
        address spell = vm.addr(1);
        delayedAdmin.schedule(spell);
        assertEq(gateway.relySchedule(spell), block.timestamp + 48 hours);
        delayedAdmin.cancelSchedule(spell);
        assertEq(gateway.relySchedule(spell), 0);
        vm.warp(block.timestamp + 49 hours);
        vm.expectRevert("ConnectorGateway/spell-not-scheduled");
        gateway.relySpell(spell);
    }

    function testUnauthorizedCancelFails() public {
        address spell = vm.addr(1);
        delayedAdmin.schedule(spell);
        vm.expectRevert("ConnectorAdmin/not-authorized");
        vm.prank(spell);
        delayedAdmin.cancelSchedule(spell);
    }

    //------ delayed 24hr admin tests ------//

    function test24hrRelyWorks() public {
        address spell = vm.addr(1);
        centChainConnector.incomingScheduleRely(spell);
        vm.warp(block.timestamp + 25 hours);
        gateway.relySpell(spell);
        assertEq(gateway.wards(spell), 1);
    }

    function test24hrRelyFailsBefore24hours() public {
        address spell = vm.addr(1);
        centChainConnector.incomingScheduleRely(spell);
        vm.warp(block.timestamp + 23 hours);
        vm.expectRevert("ConnectorGateway/spell-not-ready");
        gateway.relySpell(spell);
    }

    function test24hrRelyFailsAfterGracePeriod() public {
        address spell = vm.addr(1);
        centChainConnector.incomingScheduleRely(spell);
        vm.warp(block.timestamp + 24 hours + gateway.GRACE_PERIOD());
        vm.expectRevert("ConnectorGateway/spell-too-old");
        gateway.relySpell(spell);
    }

    //------ helpers ------//

    function newErc20(string memory name, string memory symbol, uint8 decimals) internal returns (ERC20) {
        ERC20 erc20 = new ERC20(decimals);
        erc20.file("name", name);
        erc20.file("symbol", symbol);

        return erc20;
    }
}
