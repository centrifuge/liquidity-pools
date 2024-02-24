// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import "test/BaseTest.sol";

contract GatewayTest is BaseTest {
    // Deployment
    function testDeployment(address nonWard) public {
        vm.assume(nonWard != address(root) && nonWard != address(this));

        // values set correctly
        assertEq(address(gateway.investmentManager()), address(investmentManager));
        assertEq(address(gateway.poolManager()), address(poolManager));
        assertEq(address(gateway.root()), address(root));
        assertEq(address(investmentManager.gateway()), address(gateway));
        assertEq(address(poolManager.gateway()), address(gateway));

        // router setup
        assertEq(address(gateway.outgoingRouter()), address(aggregator));
        assertTrue(gateway.incomingRouters(address(aggregator)));

        // aggregator setup
        assertEq(address(aggregator.gateway()), address(gateway));
        assertEq(aggregator.quorum(), 3);
        assertEq(aggregator.routers(0), address(router1));
        assertEq(aggregator.routers(1), address(router2));
        assertEq(aggregator.routers(2), address(router3));

        // permissions set correctly
        assertEq(gateway.wards(address(root)), 1);
        assertEq(aggregator.wards(address(root)), 1);
        assertEq(gateway.wards(nonWard), 0);
        assertEq(aggregator.wards(nonWard), 0);
    }

    // --- Administration ---
    function testFile() public {
        // fail: unrecognized param
        vm.expectRevert(bytes("Gateway/file-unrecognized-param"));
        gateway.file("random", self);

        assertEq(address(gateway.poolManager()), address(poolManager));
        assertEq(address(gateway.investmentManager()), address(investmentManager));
        // success
        gateway.file("poolManager", self);
        assertEq(address(gateway.poolManager()), self);
        gateway.file("investmentManager", self);
        assertEq(address(gateway.investmentManager()), self);

        // remove self from wards
        gateway.deny(self);
        // auth fail
        vm.expectRevert(bytes("Auth/not-authorized"));
        gateway.file("poolManager", self);
    }

    function testAddRouter(address router) public {
        vm.assume(router.code.length == 0);

        assertTrue(!gateway.incomingRouters(router)); // router not added

        //success
        gateway.addIncomingRouter(router);
        assertTrue(gateway.incomingRouters(router));

        // remove self from wards
        gateway.deny(self);
        // auth fail
        vm.expectRevert(bytes("Auth/not-authorized"));
        gateway.addIncomingRouter(router);
    }

    function testRemoveRouter(address router) public {
        vm.assume(router.code.length == 0);

        gateway.addIncomingRouter(router);
        assertTrue(gateway.incomingRouters(router));

        //success
        gateway.removeIncomingRouter(router);
        assertTrue(!gateway.incomingRouters(router));

        // remove self from wards
        gateway.deny(self);
        // auth fail
        vm.expectRevert(bytes("Auth/not-authorized"));
        gateway.removeIncomingRouter(router);
    }

    function testUpdateOutgoingRouter(address router) public {
        vm.assume(router.code.length == 0);

        assertTrue(address(gateway.outgoingRouter()) != router);

        gateway.updateOutgoingRouter(router);
        assertTrue(address(gateway.outgoingRouter()) == router);

        // remove self from wards
        gateway.deny(self);
        // auth fail
        vm.expectRevert(bytes("Auth/not-authorized"));
        gateway.updateOutgoingRouter(router);
    }

    // --- Permissions ---
    // onlyIncomingRouter can call
    function testOnlyIncomingRouterCanCall() public {
        bytes memory message = hex"020000000000bce1a4";
        assertTrue(!gateway.incomingRouters(self));

        // fail -> self not incoming router
        vm.expectRevert(bytes("Gateway/only-router-allowed-to-call"));
        gateway.handle(message);

        //success
        gateway.addIncomingRouter(self);
        assertTrue(gateway.incomingRouters(self));

        gateway.handle(message);
    }

    function testOnlyPoolManagerCanCall(uint64 poolId) public {
        assertTrue(address(gateway.poolManager()) != self);

        // fail -> self not pool manager
        vm.expectRevert(bytes("Gateway/invalid-manager"));
        gateway.send(abi.encodePacked(uint8(MessagesLib.Call.AddPool), poolId));

        gateway.file("poolManager", self);
        gateway.send(abi.encodePacked(uint8(MessagesLib.Call.AddPool), poolId));
    }

    function testOnlyInvestmentManagerCanCall(uint64 poolId) public {
        assertTrue(address(gateway.investmentManager()) != self);

        // fail -> self not investment manager
        vm.expectRevert(bytes("Gateway/invalid-manager"));
        gateway.send(abi.encodePacked(uint8(MessagesLib.Call.AddPool), poolId));

        gateway.file("investmentManager", self);
        gateway.send(abi.encodePacked(uint8(MessagesLib.Call.AddPool), poolId));
    }
}
