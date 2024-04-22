// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import "test/BaseTest.sol";
import "test/mocks/MockManager.sol";

contract GatewayTest is BaseTest {
    // Deployment
    function testDeployment(address nonWard) public {
        vm.assume(
            nonWard != address(root) && nonWard != address(delayedAdmin) && nonWard != address(this)
                && nonWard != address(aggregator)
        );

        // values set correctly
        assertEq(address(gateway.investmentManager()), address(investmentManager));
        assertEq(address(gateway.poolManager()), address(poolManager));
        assertEq(address(gateway.root()), address(root));
        assertEq(address(investmentManager.gateway()), address(gateway));
        assertEq(address(poolManager.gateway()), address(gateway));
        assertEq(address(gateway.aggregator()), address(aggregator));

        // aggregator setup
        assertEq(address(aggregator.gateway()), address(gateway));
        assertEq(aggregator.quorum(), 3);
        assertEq(aggregator.routers(0), address(router1));
        assertEq(aggregator.routers(1), address(router2));
        assertEq(aggregator.routers(2), address(router3));

        // permissions set correctly
        assertEq(gateway.wards(address(root)), 1);
        assertEq(aggregator.wards(address(root)), 1);
        assertEq(aggregator.wards(address(delayedAdmin)), 1);
        assertEq(gateway.wards(nonWard), 0);
        assertEq(aggregator.wards(nonWard), 0);
    }

    // --- Administration ---
    function testFile() public {
        // fail: unrecognized param
        vm.expectRevert(bytes("Gateway/file-unrecognized-param"));
        gateway.file("random", self);

        vm.expectRevert(bytes("Gateway/file-unrecognized-param"));
        gateway.file("random", uint8(1), self);

        assertEq(address(gateway.poolManager()), address(poolManager));
        assertEq(address(gateway.investmentManager()), address(investmentManager));
        assertEq(address(gateway.aggregator()), address(aggregator));

        // success
        gateway.file("poolManager", self);
        assertEq(address(gateway.poolManager()), self);
        gateway.file("investmentManager", self);
        assertEq(address(gateway.investmentManager()), self);
        gateway.file("aggregator", self);
        assertEq(address(gateway.aggregator()), self);

        // remove self from wards
        gateway.deny(self);
        // auth fail
        vm.expectRevert(bytes("Auth/not-authorized"));
        gateway.file("poolManager", self);
    }

    // --- Permissions ---
    function testOnlyWardCanCall() public {
        bytes memory message = hex"020000000000bce1a4";

        vm.expectRevert(bytes("Auth/not-authorized"));
        vm.prank(randomUser);
        gateway.handle(message);

        //success
        gateway.rely(randomUser);
        vm.prank(randomUser);
        gateway.handle(message);
    }

    function testOnlyManagersCanCall(uint64 poolId) public {
        vm.expectRevert(bytes("Gateway/invalid-manager"));
        gateway.send(abi.encodePacked(uint8(MessagesLib.Call.AddPool), poolId));

        gateway.file("poolManager", self);
        gateway.send(abi.encodePacked(uint8(MessagesLib.Call.AddPool), poolId));

        gateway.file("poolManager", address(poolManager));
        vm.expectRevert(bytes("Gateway/invalid-manager"));
        gateway.send(abi.encodePacked(uint8(MessagesLib.Call.AddPool), poolId));

        gateway.file("investmentManager", self);
        gateway.send(abi.encodePacked(uint8(MessagesLib.Call.AddPool), poolId));
    }

    // --- Dynamic managers ---
    function testCustomManager() public {
        MockManager mgr = new MockManager();

        bytes memory message = abi.encodePacked(uint8(40));
        vm.expectRevert(bytes("Gateway/unregistered-message-id"));
        gateway.handle(message);

        assertEq(mgr.received(message), 0);

        gateway.file("message", 40, address(mgr));
        gateway.handle(message);

        assertEq(mgr.received(message), 1);
        assertEq(mgr.values_bytes("handle_message"), message);
    }
}
