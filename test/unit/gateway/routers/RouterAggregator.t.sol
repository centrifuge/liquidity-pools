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

    function testExecution() public {
        aggregator.file("routerId", router1, 0);
        aggregator.file("routerId", router2, 1);
        aggregator.file("routerId", router3, 2);
        aggregator.file("routers", routers);
        aggregator.file("quorum", 2);

        bytes memory firstPayload = MessagesLib.formatAddPool(1);
        bytes memory secondPayload = MessagesLib.formatAddPool(2);

        vm.prank(router1);
        aggregator.execute(firstPayload);
        assertEq(gatewayMock.handled(firstPayload), 0);

        vm.prank(router2);
        aggregator.execute(firstPayload);
        assertEq(gatewayMock.handled(firstPayload), 1);

        vm.prank(router3);
        aggregator.execute(firstPayload);
        assertEq(gatewayMock.handled(firstPayload), 1);

        // Immediately executed because payload matches
        vm.prank(router1);
        aggregator.execute(firstPayload);
        assertEq(gatewayMock.handled(firstPayload), 2);

        vm.prank(router2);
        aggregator.execute(firstPayload);
        assertEq(gatewayMock.handled(firstPayload), 2);

        vm.prank(router3);
        aggregator.execute(firstPayload);
        assertEq(gatewayMock.handled(firstPayload), 2);

        // Not immediately executed
        vm.prank(router1);
        aggregator.execute(secondPayload);
        assertEq(gatewayMock.handled(secondPayload), 0);

        vm.prank(router2);
        aggregator.execute(secondPayload);
        assertEq(gatewayMock.handled(secondPayload), 1);

        vm.prank(router3);
        aggregator.execute(secondPayload);
        assertEq(gatewayMock.handled(secondPayload), 1);

    }
}
