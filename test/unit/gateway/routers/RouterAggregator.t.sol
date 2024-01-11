// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import "test/BaseTest.sol";
import {RouterAggregator} from "src/gateway/routers/RouterAggregator.sol";
import {GatewayMock} from "test/mocks/GatewayMock.sol";
import {MockRouter} from "test/mocks/MockRouter.sol";

contract RouterAggregatorTest is BaseTest {
    RouterAggregator aggregator;

    GatewayMock gatewayMock;
    MockRouter router1;
    MockRouter router2;
    MockRouter router3;
    address[] routers;

    function setUp() public override {
        super.setUp();

        gatewayMock = new GatewayMock();

        aggregator = new RouterAggregator();
        aggregator.file("gateway", address(gatewayMock));

        router1 = new MockRouter();
        router1.file("gateway", address(aggregator));
        router2 = new MockRouter();
        router2.file("gateway", address(aggregator));
        router3 = new MockRouter();
        router3.file("gateway", address(aggregator));

        routers.push(address(router1));
        routers.push(address(router2));
        routers.push(address(router3));
    }

    function testFile() public {
        vm.expectRevert(bytes("RouterAggregator/file-unrecognized-param"));
        aggregator.file("random", self);

        aggregator.file("gateway", randomUser);
        assertEq(address(aggregator.gateway()), randomUser);

        aggregator.deny(self);
        vm.expectRevert(bytes("Auth/not-authorized"));
        aggregator.file("gateway", randomUser);
    }

    function testIncomingAggregatedMessages() public {
        aggregator.file("routers", routers, 2);

        bytes memory firstPayload = MessagesLib.formatAddPool(1);
        bytes memory firstPayloadProof = MessagesLib.formatMessageProof(MessagesLib.formatAddPool(1));

        vm.expectRevert(bytes("RouterAggregator/invalid-router"));
        aggregator.handle(firstPayload);

        // Executes after quorum is reached
        router1.execute(firstPayload);
        assertEq(gatewayMock.handled(firstPayload), 0);

        router2.execute(firstPayloadProof);
        assertEq(gatewayMock.handled(firstPayload), 1);

        router3.execute(firstPayloadProof);
        assertEq(gatewayMock.handled(firstPayload), 1);

        // Resending same payload works
        // Immediately executes because of 3rd proof from previous matching payload
        router1.execute(firstPayload);
        assertEq(gatewayMock.handled(firstPayload), 2);

        router2.execute(firstPayloadProof);
        assertEq(gatewayMock.handled(firstPayload), 2);

        router3.execute(firstPayloadProof);
        assertEq(gatewayMock.handled(firstPayload), 2);

        // Sending another payload works
        bytes memory secondPayload = MessagesLib.formatAddPool(2);
        bytes memory secondPayloadProof = MessagesLib.formatMessageProof(MessagesLib.formatAddPool(2));

        router1.execute(secondPayload);
        assertEq(gatewayMock.handled(secondPayload), 0);

        router2.execute(secondPayloadProof);
        assertEq(gatewayMock.handled(secondPayload), 1);

        router3.execute(secondPayloadProof);
        assertEq(gatewayMock.handled(secondPayload), 1);

        // Swapping order of payload vs proofs works
        bytes memory thirdPayload = MessagesLib.formatAddPool(3);
        bytes memory thirdPayloadProof = MessagesLib.formatMessageProof(MessagesLib.formatAddPool(3));

        router1.execute(thirdPayloadProof);
        assertEq(gatewayMock.handled(thirdPayload), 0);

        router2.execute(thirdPayloadProof);
        assertEq(gatewayMock.handled(thirdPayload), 0);

        router3.execute(thirdPayload);
        assertEq(gatewayMock.handled(thirdPayload), 1);
    }

    function testOutgoingAggregatedMessages() public {
        aggregator.file("routers", routers, 2);

        bytes memory firstPayload = MessagesLib.formatAddPool(1);
        bytes memory firstPayloadProof = MessagesLib.formatMessageProof(MessagesLib.formatAddPool(1));

        assertEq(router1.sent(firstPayload), 0);
        assertEq(router2.sent(firstPayload), 0);
        assertEq(router3.sent(firstPayload), 0);
        assertEq(router1.sent(firstPayloadProof), 0);
        assertEq(router2.sent(firstPayloadProof), 0);
        assertEq(router3.sent(firstPayloadProof), 0);

        vm.expectRevert(bytes("RouterAggregator/only-gateway-allowed-to-call"));
        aggregator.send(firstPayload);

        vm.prank(address(gatewayMock));
        aggregator.send(firstPayload);

        assertEq(router1.sent(firstPayload), 1);
        assertEq(router2.sent(firstPayload), 0);
        assertEq(router3.sent(firstPayload), 0);
        assertEq(router1.sent(firstPayloadProof), 0);
        assertEq(router2.sent(firstPayloadProof), 1);
        assertEq(router3.sent(firstPayloadProof), 1);
    }
}
