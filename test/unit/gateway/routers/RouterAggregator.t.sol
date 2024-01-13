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

        bytes memory firstMessage = MessagesLib.formatAddPool(1);
        bytes memory firstProof = MessagesLib.formatMessageProof(MessagesLib.formatAddPool(1));

        vm.expectRevert(bytes("RouterAggregator/invalid-router"));
        aggregator.handle(firstMessage);

        // Executes after quorum is reached
        router1.execute(firstMessage);
        assertEq(gateway.handled(firstMessage), 0);
        assertEq(aggregator.confirmations(keccak256(firstMessage)), 1);

        router2.execute(firstProof);
        assertEq(gateway.handled(firstMessage), 1);
        assertEq(aggregator.confirmations(keccak256(firstMessage)), 0);

        router3.execute(firstProof);
        assertEq(gateway.handled(firstMessage), 1);
        assertEq(aggregator.confirmations(keccak256(firstMessage)), 1);

        // Resending same message works
        // Immediately executes because of 3rd proof from previous matching message
        router1.execute(firstMessage);
        assertEq(gateway.handled(firstMessage), 2);
        assertEq(aggregator.confirmations(keccak256(firstMessage)), 0);

        router2.execute(firstProof);
        assertEq(gateway.handled(firstMessage), 2);
        assertEq(aggregator.confirmations(keccak256(firstMessage)), 1);

        router3.execute(firstProof);
        assertEq(gateway.handled(firstMessage), 2);
        assertEq(aggregator.confirmations(keccak256(firstMessage)), 2);

        // Sending another message works
        bytes memory secondMessage = MessagesLib.formatAddPool(2);
        bytes memory secondProof = MessagesLib.formatMessageProof(MessagesLib.formatAddPool(2));

        router1.execute(secondMessage);
        assertEq(gateway.handled(secondMessage), 0);
        assertEq(aggregator.confirmations(keccak256(secondMessage)), 1);

        router2.execute(secondProof);
        assertEq(gateway.handled(secondMessage), 1);
        assertEq(aggregator.confirmations(keccak256(secondMessage)), 0);

        router3.execute(secondProof);
        assertEq(gateway.handled(secondMessage), 1);
        assertEq(aggregator.confirmations(keccak256(secondMessage)), 1);

        // Swapping order of message vs proofs works
        bytes memory thirdMessage = MessagesLib.formatAddPool(3);
        bytes memory thirdProof = MessagesLib.formatMessageProof(MessagesLib.formatAddPool(3));

        router1.execute(thirdProof);
        assertEq(gateway.handled(thirdMessage), 0);
        assertEq(aggregator.confirmations(keccak256(thirdMessage)), 1);

        router2.execute(thirdProof);
        assertEq(gateway.handled(thirdMessage), 0);
        assertEq(aggregator.confirmations(keccak256(thirdMessage)), 2);

        router3.execute(thirdMessage);
        assertEq(gateway.handled(thirdMessage), 1);
        assertEq(aggregator.confirmations(keccak256(thirdMessage)), 0);
    }

    function testOutgoingAggregatedMessages() public {
        aggregator.file("routers", mockRouters, 2);

        bytes memory message = MessagesLib.formatAddPool(1);
        bytes memory proof = MessagesLib.formatMessageProof(MessagesLib.formatAddPool(1));

        assertEq(router1.sent(message), 0);
        assertEq(router2.sent(message), 0);
        assertEq(router3.sent(message), 0);
        assertEq(router1.sent(proof), 0);
        assertEq(router2.sent(proof), 0);
        assertEq(router3.sent(proof), 0);

        vm.expectRevert(bytes("RouterAggregator/only-gateway-allowed-to-call"));
        aggregator.send(message);

        vm.prank(address(gateway));
        aggregator.send(message);

        assertEq(router1.sent(message), 1);
        assertEq(router2.sent(message), 0);
        assertEq(router3.sent(message), 0);
        assertEq(router1.sent(proof), 0);
        assertEq(router2.sent(proof), 1);
        assertEq(router3.sent(proof), 1);
    }

    // TODO testRecoverIncomingAggregatedMessages

    function testMessagesCannotBeReplayed(
        uint8 numRouters,
        uint8 quorum,
        uint8 numParallelDuplicateMessages_,
        uint256 entropy
    ) public {
        numRouters = uint8(bound(numRouters, 1, aggregator.MAX_ROUTER_COUNT()));
        quorum = uint8(bound(quorum, 1, _min(numRouters, aggregator.MAX_QUORUM())));
        uint16 numParallelDuplicateMessages = uint16(bound(numParallelDuplicateMessages_, 1, 255));

        bytes memory message = MessagesLib.formatAddPool(1);
        bytes memory proof = MessagesLib.formatMessageProof(MessagesLib.formatAddPool(1));

        // Setup random set of routers
        address[] memory testRouters = new address[](numRouters);
        for (uint256 i = 0; i < numRouters; i++) {
            testRouters[i] = address(new MockRouter(address(aggregator)));
        }
        aggregator.file("routers", testRouters, quorum);

        // Generate random sequence of confirming messages and proofs
        uint256 it = 0;
        uint256 totalSent = 0;
        uint256[] memory sentPerRouter = new uint256[](numRouters);
        while (totalSent < numParallelDuplicateMessages * numRouters) {
            it++;
            uint8 randomRouterId =
                numRouters > 1 ? uint8(uint256(keccak256(abi.encodePacked(entropy, it)))) % numRouters : 0;

            if (sentPerRouter[randomRouterId] == numParallelDuplicateMessages) {
                // Already confirmed all the messages
                continue;
            }

            // Send the message or proof
            if (randomRouterId == 0) {
                MockRouter(testRouters[randomRouterId]).execute(message);
            } else {
                MockRouter(testRouters[randomRouterId]).execute(proof);
            }

            totalSent++;
            sentPerRouter[randomRouterId]++;
        }

        // Check that each message was confirmed exactly numParallelDuplicateMessages times
        for (uint256 j = 0; j < numParallelDuplicateMessages; j++) {
            assertEq(gateway.handled(message), numParallelDuplicateMessages);
        }
    }

    /// @notice Returns the smallest of two numbers.
    function _min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a > b ? b : a;
    }
}
