// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import "../TestSetup.t.sol";

contract GatewayTest is TestSetup {
    // Deployment
    function testDeployment() public {
        // values set correctly
        assertEq(address(gateway.investmentManager()), address(investmentManager));
        assertEq(address(gateway.poolManager()), address(poolManager));
        assertEq(address(gateway.root()), address(root));
        assertEq(address(investmentManager.gateway()), address(gateway));
        assertEq(address(poolManager.gateway()), address(gateway));

        // router setup
        assertEq(address(gateway.outgoingRouter()), address(mockXcmRouter));
        assertTrue(gateway.incomingRouters(address(mockXcmRouter)));

        // permissions set correctly
        assertEq(gateway.wards(address(root)), 1);
        // assertEq(gateway.wards(self), 0); // deployer has no permissions
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

    //onlyPoolManager can call
    function testOnlyPoolManagerCanCall(
        uint64 poolId,
        bytes16 trancheId,
        address sender,
        uint64 destinationChainId,
        address destinationAddress,
        bytes32 destinationAddressBytes,
        uint128 amount,
        uint128 token,
        bytes32 receiver
    ) public {
        assertTrue(address(gateway.poolManager()) != self);

        // fail -> self not pool manager
        vm.expectRevert(bytes("Gateway/only-pool-manager-allowed-to-call"));
        gateway.transferTrancheTokensToCentrifuge(poolId, trancheId, sender, destinationAddressBytes, amount);

        vm.expectRevert(bytes("Gateway/only-pool-manager-allowed-to-call"));
        gateway.transferTrancheTokensToEVM(poolId, trancheId, sender, destinationChainId, destinationAddress, amount);

        vm.expectRevert(bytes("Gateway/only-pool-manager-allowed-to-call"));
        gateway.transfer(token, sender, receiver, amount);

        gateway.file("poolManager", self);
        gateway.transferTrancheTokensToCentrifuge(poolId, trancheId, sender, destinationAddressBytes, amount);
        gateway.transferTrancheTokensToEVM(poolId, trancheId, sender, destinationChainId, destinationAddress, amount);
        gateway.transfer(token, sender, receiver, amount);
    }

    //onlyInvestmentManager can call
    function testOnlyInvestmentManagerCanCall(
        uint64 poolId,
        bytes16 trancheId,
        address investor,
        uint128 currency,
        uint128 currencyAmount,
        uint128 trancheTokenAmount
    ) public {
        assertTrue(address(gateway.investmentManager()) != self);

        // fail -> self investment manager
        vm.expectRevert(bytes("Gateway/only-investment-manager-allowed-to-call"));
        gateway.increaseInvestOrder(poolId, trancheId, investor, currency, currencyAmount);

        vm.expectRevert(bytes("Gateway/only-investment-manager-allowed-to-call"));
        gateway.decreaseInvestOrder(poolId, trancheId, investor, currency, currencyAmount);

        vm.expectRevert(bytes("Gateway/only-investment-manager-allowed-to-call"));
        gateway.increaseRedeemOrder(poolId, trancheId, investor, currency, trancheTokenAmount);

        vm.expectRevert(bytes("Gateway/only-investment-manager-allowed-to-call"));
        gateway.decreaseRedeemOrder(poolId, trancheId, investor, currency, trancheTokenAmount);

        vm.expectRevert(bytes("Gateway/only-investment-manager-allowed-to-call"));
        gateway.collectInvest(poolId, trancheId, investor, currency);

        vm.expectRevert(bytes("Gateway/only-investment-manager-allowed-to-call"));
        gateway.collectRedeem(poolId, trancheId, investor, currency);

        vm.expectRevert(bytes("Gateway/only-investment-manager-allowed-to-call"));
        gateway.cancelInvestOrder(poolId, trancheId, investor, currency);

        vm.expectRevert(bytes("Gateway/only-investment-manager-allowed-to-call"));
        gateway.cancelRedeemOrder(poolId, trancheId, investor, currency);

        gateway.file("investmentManager", self);
        // success
        gateway.increaseInvestOrder(poolId, trancheId, investor, currency, currencyAmount);
        gateway.decreaseInvestOrder(poolId, trancheId, investor, currency, currencyAmount);
        gateway.increaseRedeemOrder(poolId, trancheId, investor, currency, trancheTokenAmount);
        gateway.decreaseRedeemOrder(poolId, trancheId, investor, currency, trancheTokenAmount);
        gateway.collectInvest(poolId, trancheId, investor, currency);
        gateway.collectRedeem(poolId, trancheId, investor, currency);
        gateway.cancelInvestOrder(poolId, trancheId, investor, currency);
        gateway.cancelRedeemOrder(poolId, trancheId, investor, currency);
    }
}
