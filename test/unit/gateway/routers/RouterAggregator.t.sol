// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import "test/BaseTest.sol";
import {RouterAggregator} from "src/gateway/routers/RouterAggregator.sol";
import {GatewayMock} from "test/mocks/GatewayMock.sol";
import {MockRouter} from "test/mocks/MockRouter.sol";

contract RouterAggregatorTest is Test {
    RouterAggregator aggregator;
    GatewayMock gateway;
    MockRouter router1;
    MockRouter router2;
    MockRouter router3;
    address[] mockRouters;

    function setUp() public {
        gateway = new GatewayMock();
        aggregator = new RouterAggregator(address(gateway));

        router1 = new MockRouter(address(aggregator));
        router2 = new MockRouter(address(aggregator));
        router3 = new MockRouter(address(aggregator));

        mockRouters.push(address(router1));
        mockRouters.push(address(router2));
        mockRouters.push(address(router3));
    }

    function testFile() public {
        // TODO: RouterAggregator/exceeds-max-router-count

        vm.expectRevert(bytes("RouterAggregator/less-than-min-quorum"));
        aggregator.file("routers", mockRouters, 0);

        // TODO: RouterAggregator/exceeds-max-quorum

        vm.expectRevert(bytes("RouterAggregator/quorum-exceeds-num-routers"));
        aggregator.file("routers", mockRouters, 4);

        aggregator.deny(address(this));
        vm.expectRevert(bytes("Auth/not-authorized"));
        aggregator.file("routers", mockRouters, 4);
    }

    function testIncomingAggregatedMessages() public {
        aggregator.file("routers", mockRouters, 2);

        bytes memory firstPayload = MessagesLib.formatAddPool(1);
        bytes memory firstPayloadProof = MessagesLib.formatMessageProof(MessagesLib.formatAddPool(1));

        vm.expectRevert(bytes("RouterAggregator/invalid-router"));
        aggregator.handle(firstPayload);

        // Executes after quorum is reached
        router1.execute(firstPayload);
        assertEq(gateway.handled(firstPayload), 0);

        router2.execute(firstPayloadProof);
        assertEq(gateway.handled(firstPayload), 1);

        router3.execute(firstPayloadProof);
        assertEq(gateway.handled(firstPayload), 1);

        // Resending same payload works
        // Immediately executes because of 3rd proof from previous matching payload
        router1.execute(firstPayload);
        assertEq(gateway.handled(firstPayload), 2);

        router2.execute(firstPayloadProof);
        assertEq(gateway.handled(firstPayload), 2);

        router3.execute(firstPayloadProof);
        assertEq(gateway.handled(firstPayload), 2);

        // Sending another payload works
        bytes memory secondPayload = MessagesLib.formatAddPool(2);
        bytes memory secondPayloadProof = MessagesLib.formatMessageProof(MessagesLib.formatAddPool(2));

        router1.execute(secondPayload);
        assertEq(gateway.handled(secondPayload), 0);

        router2.execute(secondPayloadProof);
        assertEq(gateway.handled(secondPayload), 1);

        router3.execute(secondPayloadProof);
        assertEq(gateway.handled(secondPayload), 1);

        // Swapping order of payload vs proofs works
        bytes memory thirdPayload = MessagesLib.formatAddPool(3);
        bytes memory thirdPayloadProof = MessagesLib.formatMessageProof(MessagesLib.formatAddPool(3));

        router1.execute(thirdPayloadProof);
        assertEq(gateway.handled(thirdPayload), 0);

        router2.execute(thirdPayloadProof);
        assertEq(gateway.handled(thirdPayload), 0);

        router3.execute(thirdPayload);
        assertEq(gateway.handled(thirdPayload), 1);
    }

    function testOutgoingAggregatedMessages() public {
        aggregator.file("routers", mockRouters, 2);

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

        vm.prank(address(gateway));
        aggregator.send(firstPayload);

        assertEq(router1.sent(firstPayload), 1);
        assertEq(router2.sent(firstPayload), 0);
        assertEq(router3.sent(firstPayload), 0);
        assertEq(router1.sent(firstPayloadProof), 0);
        assertEq(router2.sent(firstPayloadProof), 1);
        assertEq(router3.sent(firstPayloadProof), 1);
    }

    // TODO testRecoverIncomingAggregatedMessages

    function testMessagesCannotBeReplayed(
        uint8 numRouters,
        uint8 quorum,
        uint8 numParallelDuplicateMessages,
        uint256 entropy
    ) public {
        numRouters = uint8(bound(numRouters, 1, aggregator.MAX_ROUTER_COUNT()));
        quorum = uint8(bound(quorum, 1, _min(numRouters, aggregator.MAX_QUORUM())));
        numParallelDuplicateMessages = uint8(bound(numParallelDuplicateMessages, 2, 4)); // TODO: increase

        bytes memory payload = MessagesLib.formatAddPool(1);
        bytes memory proof = MessagesLib.formatMessageProof(MessagesLib.formatAddPool(1));

        // Setup routers
        address[] memory testRouters = new address[](numRouters);
        for (uint256 i = 0; i < numRouters; i++) {
            testRouters[i] = address(new MockRouter(address(aggregator)));
        }
        aggregator.file("routers", testRouters, quorum);

        // Generate random sequence of confirming payloads and proofs
        uint256 it = 0;
        uint256 totalSent = 0;
        uint256[] memory sentPerRouter = new uint256[](numRouters);
        while (totalSent < numParallelDuplicateMessages * numRouters) {
            it++;
            uint8 randomRouterId =
                numRouters > 1 ? uint8(uint256(keccak256(abi.encodePacked(entropy, it)))) % numRouters : 0;

            if (sentPerRouter[randomRouterId] == numParallelDuplicateMessages) {
                // Already confirmed all the messages
                // TODO: see if we can make this more efficient (not just skipping iterations in the loop)
                continue;
            }

            // Send the payload or proof
            if (randomRouterId == 0) {
                MockRouter(testRouters[randomRouterId]).execute(payload);
            } else {
                MockRouter(testRouters[randomRouterId]).execute(proof);
            }

            totalSent++;
            sentPerRouter[randomRouterId]++;
        }

        // Check that each message was confirmed exactly numParallelDuplicateMessages times
        for (uint256 j = 0; j < numParallelDuplicateMessages; j++) {
            assertEq(gateway.handled(payload), numParallelDuplicateMessages);
        }
    }

    /// @notice Returns the smallest of two numbers.
    function _min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a > b ? b : a;
    }
}
