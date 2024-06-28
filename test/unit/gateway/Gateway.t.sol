// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import "test/BaseTest.sol";
import "test/mocks/MockManager.sol";

contract GatewayTest is BaseTest {
    // Deployment
    function testDeployment(address nonWard) public {
        vm.assume(
            nonWard != address(root) && nonWard != address(guardian) && nonWard != address(this)
                && nonWard != address(gateway)
        );

        // values set correctly
        assertEq(address(gateway.investmentManager()), address(investmentManager));
        assertEq(address(gateway.poolManager()), address(poolManager));
        assertEq(address(gateway.root()), address(root));
        assertEq(address(investmentManager.gateway()), address(gateway));
        assertEq(address(poolManager.gateway()), address(gateway));

        // gateway setup
        assertEq(gateway.quorum(), 3);
        assertEq(gateway.adapters(0), address(adapter1));
        assertEq(gateway.adapters(1), address(adapter2));
        assertEq(gateway.adapters(2), address(adapter3));

        // permissions set correctly
        assertEq(gateway.wards(address(root)), 1);
        assertEq(gateway.wards(address(guardian)), 1);
        assertEq(gateway.wards(nonWard), 0);
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
        assertEq(address(gateway.gasService()), address(mockedGasService));

        // success
        gateway.file("poolManager", self);
        assertEq(address(gateway.poolManager()), self);
        gateway.file("investmentManager", self);
        assertEq(address(gateway.investmentManager()), self);
        gateway.file("gasService", self);
        assertEq(address(gateway.gasService()), self);

        // remove self from wards
        gateway.deny(self);
        // auth fail
        vm.expectRevert(bytes("Auth/not-authorized"));
        gateway.file("poolManager", self);
    }

    // --- Permissions ---
    function testOnlyAdaptersCanCall() public {
        bytes memory message = hex"020000000000bce1a4";

        vm.expectRevert(bytes("Gateway/invalid-adapter"));
        vm.prank(randomUser);
        gateway.handle(message);

        //success
        vm.prank(address(adapter1));
        gateway.handle(message);
    }

    function testOnlyManagersCanCall(uint64 poolId) public {
        vm.expectRevert(bytes("Gateway/invalid-manager"));
        gateway.send(abi.encodePacked(uint8(MessagesLib.Call.AddPool), poolId), self);

        gateway.file("poolManager", self);
        gateway.send(abi.encodePacked(uint8(MessagesLib.Call.AddPool), poolId), self);

        gateway.file("poolManager", address(poolManager));
        vm.expectRevert(bytes("Gateway/invalid-manager"));
        gateway.send(abi.encodePacked(uint8(MessagesLib.Call.AddPool), poolId), self);

        gateway.file("investmentManager", self);
        gateway.send(abi.encodePacked(uint8(MessagesLib.Call.AddPool), poolId), self);
    }

    // --- Dynamic managers ---
    function testCustomManager() public {
        uint8 messageId = 40;
        address[] memory adapters = new address[](1);
        adapters[0] = address(adapter1);

        gateway.file("adapters", adapters);

        MockManager mgr = new MockManager();

        bytes memory message = abi.encodePacked(messageId);
        vm.expectRevert(bytes("Gateway/unregistered-message-id"));
        vm.prank(address(adapter1));
        gateway.handle(message);

        assertEq(mgr.received(message), 0);

        gateway.file("message", messageId, address(mgr));
        vm.prank(address(adapter1));
        gateway.handle(message);

        assertEq(mgr.received(message), 1);
        assertEq(mgr.values_bytes("handle_message"), message);
    }
}
