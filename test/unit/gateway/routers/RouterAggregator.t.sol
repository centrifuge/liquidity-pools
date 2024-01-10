// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import "test/BaseTest.sol";
import {RouterAggregator} from "src/gateway/routers/RouterAggregator.sol";
import {GatewayMock} from "test/mocks/GatewayMock.sol";

contract RouterAggregatorTest is BaseTest {
    RouterAggregator aggregator;
    GatewayMock gatewayMock;

    address router1 = makeAddr("router1");
    address router2 = makeAddr("router2");
    address router3 = makeAddr("router3");
    address[] routers;

    function setUp() public override {
        super.setUp();
        gatewayMock = new GatewayMock();
        aggregator = new RouterAggregator();
        aggregator.file("gateway", address(gatewayMock));
        routers.push(router1);
        routers.push(router2);
        routers.push(router3);
    }

    function testIncoming() public {
        aggregator.file("routers", routers, 2);

        bytes memory firstPayload = MessagesLib.formatAddPool(1);
        bytes memory firstPayloadProof = MessagesLib.formatMessageProof(MessagesLib.formatAddPool(1));

        // Executes after quorum is reached
        vm.prank(router1);
        aggregator.execute(firstPayload);
        assertEq(gatewayMock.handled(firstPayload), 0);

        vm.prank(router2);
        aggregator.execute(firstPayloadProof);
        assertEq(gatewayMock.handled(firstPayload), 1);

        vm.prank(router3);
        aggregator.execute(firstPayloadProof);
        assertEq(gatewayMock.handled(firstPayload), 1);

        // Resending same payload works
        // Immediately executes because of 3rd proof from previous matching payload
        vm.prank(router1);
        aggregator.execute(firstPayload);
        assertEq(gatewayMock.handled(firstPayload), 2);

        vm.prank(router2);
        aggregator.execute(firstPayloadProof);
        assertEq(gatewayMock.handled(firstPayload), 2);

        vm.prank(router3);
        aggregator.execute(firstPayloadProof);
        assertEq(gatewayMock.handled(firstPayload), 2);

        // Sending another payload works
        bytes memory secondPayload = MessagesLib.formatAddPool(2);
        bytes memory secondPayloadProof = MessagesLib.formatMessageProof(MessagesLib.formatAddPool(2));

        vm.prank(router1);
        aggregator.execute(secondPayload);
        assertEq(gatewayMock.handled(secondPayload), 0);

        vm.prank(router2);
        aggregator.execute(secondPayloadProof);
        assertEq(gatewayMock.handled(secondPayload), 1);

        vm.prank(router3);
        aggregator.execute(secondPayloadProof);
        assertEq(gatewayMock.handled(secondPayload), 1);

        // Swapping order of payload vs proofs works
        bytes memory thirdPayload = MessagesLib.formatAddPool(3);
        bytes memory thirdPayloadProof = MessagesLib.formatMessageProof(MessagesLib.formatAddPool(3));

        vm.prank(router1);
        aggregator.execute(thirdPayloadProof);
        assertEq(gatewayMock.handled(thirdPayload), 0);

        vm.prank(router2);
        aggregator.execute(thirdPayloadProof);
        assertEq(gatewayMock.handled(thirdPayload), 0);

        vm.prank(router3);
        aggregator.execute(thirdPayload);
        assertEq(gatewayMock.handled(thirdPayload), 1);
    }

    // TODO: set up mock router and test sending messages
}
