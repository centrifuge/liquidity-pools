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
    MockRouter router4;
    address[] threeMockRouters;
    address[] fourMockRouters;
    address[] nineMockRouters;

    function setUp() public {
        gateway = new GatewayMock();
        aggregator = new RouterAggregator(address(gateway));

        router1 = new MockRouter(address(aggregator));
        vm.label(address(router1), "MockRouter1");
        router2 = new MockRouter(address(aggregator));
        vm.label(address(router2), "MockRouter2");
        router3 = new MockRouter(address(aggregator));
        vm.label(address(router3), "MockRouter3");
        router4 = new MockRouter(address(aggregator));
        vm.label(address(router4), "MockRouter4");

        threeMockRouters.push(address(router1));
        threeMockRouters.push(address(router2));
        threeMockRouters.push(address(router3));

        fourMockRouters.push(address(router1));
        fourMockRouters.push(address(router2));
        fourMockRouters.push(address(router3));
        fourMockRouters.push(address(router4));

        nineMockRouters.push(address(router1));
        nineMockRouters.push(address(router1));
        nineMockRouters.push(address(router1));
        nineMockRouters.push(address(router1));
        nineMockRouters.push(address(router1));
        nineMockRouters.push(address(router1));
        nineMockRouters.push(address(router1));
        nineMockRouters.push(address(router1));
        nineMockRouters.push(address(router1));
    }

    function testFileRouters() public {
        aggregator.file("routers", threeMockRouters);
        assertEq(aggregator.routers(0), address(router1));
        assertEq(aggregator.routers(1), address(router2));
        assertEq(aggregator.routers(2), address(router3));
        vm.expectRevert(bytes(""));
        assertEq(aggregator.routers(3), address(0));

        (uint8 validRouter1Id, uint8 validRouter1Quorum) = aggregator.validRouters(address(router1));
        assertEq(validRouter1Id, 1);
        assertEq(validRouter1Quorum, 3);
        (uint8 validRouter2Id, uint8 validRouter2Quorum) = aggregator.validRouters(address(router2));
        assertEq(validRouter2Id, 2);
        assertEq(validRouter2Quorum, 3);
        (uint8 validRouter3Id, uint8 validRouter3Quorum) = aggregator.validRouters(address(router3));
        assertEq(validRouter3Id, 3);
        assertEq(validRouter3Quorum, 3);
        (uint8 invalidRouter4Id, uint8 invalidRouter4Quorum) = aggregator.validRouters(address(router4));
        assertEq(invalidRouter4Id, 0);
        assertEq(invalidRouter4Quorum, 0);

        aggregator.file("routers", fourMockRouters);
        (uint8 validRouter4Id, uint8 validRouter4Quorum) = aggregator.validRouters(address(router4));
        assertEq(validRouter4Id, 4);
        assertEq(validRouter4Quorum, 4);
        assertEq(aggregator.routers(3), address(router4));

        aggregator.file("routers", threeMockRouters);
        (invalidRouter4Id, invalidRouter4Quorum) = aggregator.validRouters(address(router4));
        assertEq(invalidRouter4Id, 0);
        assertEq(invalidRouter4Quorum, 0);
        vm.expectRevert(bytes(""));
        assertEq(aggregator.routers(3), address(0));

        vm.expectRevert(bytes("RouterAggregator/exceeds-max-router-count"));
        aggregator.file("routers", nineMockRouters);

        aggregator.deny(address(this));
        vm.expectRevert(bytes("Auth/not-authorized"));
        aggregator.file("routers", threeMockRouters);
    }

    function testUseBeforeInitialization() public {
        vm.expectRevert(bytes("RouterAggregator/invalid-router"));
        aggregator.handle(MessagesLib.formatAddPool(1));

        vm.prank(address(gateway));
        vm.expectRevert(bytes("RouterAggregator/not-initialized"));
        aggregator.send(MessagesLib.formatAddPool(1));
    }

    function testIncomingAggregatedMessages() public {
        aggregator.file("routers", threeMockRouters);

        bytes memory firstMessage = MessagesLib.formatAddPool(1);
        bytes memory firstProof = MessagesLib.formatMessageProof(MessagesLib.formatAddPool(1));

        vm.expectRevert(bytes("RouterAggregator/invalid-router"));
        aggregator.handle(firstMessage);

        // Executes after quorum is reached
        router1.execute(firstMessage);
        assertEq(gateway.handled(firstMessage), 0);
        assertConfirmations(firstMessage, 1, 0, 0, 0, 0, 0);

        router2.execute(firstProof);
        assertEq(gateway.handled(firstMessage), 0);
        assertConfirmations(firstMessage, 1, 0, 0, 0, 1, 0);

        router3.execute(firstProof);
        assertEq(gateway.handled(firstMessage), 1);
        assertConfirmations(firstMessage, 0, 0, 0, 0, 0, 0);

        // Resending same message works
        router1.execute(firstMessage);
        assertEq(gateway.handled(firstMessage), 1);
        assertConfirmations(firstMessage, 1, 0, 0, 0, 0, 0);

        router2.execute(firstProof);
        assertEq(gateway.handled(firstMessage), 1);
        assertConfirmations(firstMessage, 1, 0, 0, 0, 1, 0);

        router3.execute(firstProof);
        assertEq(gateway.handled(firstMessage), 2);
        assertConfirmations(firstMessage, 0, 0, 0, 0, 0, 0);

        // Sending another message works
        bytes memory secondMessage = MessagesLib.formatAddPool(2);
        bytes memory secondProof = MessagesLib.formatMessageProof(MessagesLib.formatAddPool(2));

        router1.execute(secondMessage);
        assertEq(gateway.handled(secondMessage), 0);
        assertConfirmations(secondMessage, 1, 0, 0, 0, 0, 0);

        router2.execute(secondProof);
        assertEq(gateway.handled(secondMessage), 0);
        assertConfirmations(secondMessage, 1, 0, 0, 0, 1, 0);

        router3.execute(secondProof);
        assertEq(gateway.handled(secondMessage), 1);
        assertConfirmations(secondMessage, 0, 0, 0, 0, 0, 0);

        // Swapping order of message vs proofs works
        bytes memory thirdMessage = MessagesLib.formatAddPool(3);
        bytes memory thirdProof = MessagesLib.formatMessageProof(MessagesLib.formatAddPool(3));

        router1.execute(thirdProof);
        assertEq(gateway.handled(thirdMessage), 0);
        assertConfirmations(thirdMessage, 0, 0, 0, 1, 0, 0);

        router2.execute(thirdProof);
        assertEq(gateway.handled(thirdMessage), 0);
        assertConfirmations(thirdMessage, 0, 0, 0, 1, 1, 0);

        router3.execute(thirdMessage);
        assertEq(gateway.handled(thirdMessage), 1);
        assertConfirmations(thirdMessage, 0, 0, 0, 0, 0, 0);
    }

    function testOneFasterPayloadRouter() public {
        aggregator.file("routers", threeMockRouters);

        bytes memory message = MessagesLib.formatAddPool(1);
        bytes memory proof = MessagesLib.formatMessageProof(MessagesLib.formatAddPool(1));

        vm.expectRevert(bytes("RouterAggregator/invalid-router"));
        aggregator.handle(message);

        // Confirm two messages by payload first
        router1.execute(message);
        router2.execute(message);
        assertEq(gateway.handled(message), 0);
        assertConfirmations(message, 1, 1, 0, 0, 0, 0);

        // Submit first proof
        router2.execute(proof);
        assertEq(gateway.handled(message), 0);
        assertConfirmations(message, 1, 1, 0, 0, 1, 0);

        // Submit second proof
        router3.execute(proof);
        assertEq(gateway.handled(message), 1);
        assertConfirmations(message, 0, 1, 0, 0, 0, 0);
    }

    function testOutgoingAggregatedMessages() public {
        aggregator.file("routers", threeMockRouters);

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

    function testRecoverFailedMessage() public {
        aggregator.file("routers", threeMockRouters);

        bytes memory message = MessagesLib.formatAddPool(1);
        bytes memory proof = MessagesLib.formatMessageProof(message);
        bytes32 messageHash = keccak256(message);

        vm.prank(address(gateway));
        aggregator.send(message);

        vm.expectRevert(bytes("RouterAggregator/invalid-router"));
        aggregator.recoverMessage(address(0), message);

        aggregator.recoverMessage(address(router2), message);
        assertEq(router1.sent(message), 1);
        assertEq(router2.sent(message), 1);
        assertEq(router3.sent(message), 0);
        assertEq(router1.sent(proof), 0);
        assertEq(router2.sent(proof), 1);
        assertEq(router3.sent(proof), 1);

        vm.expectRevert(bytes("RouterAggregator/invalid-router"));
        aggregator.recoverProof(address(0), messageHash);

        aggregator.recoverProof(address(router3), messageHash);
        assertEq(router1.sent(message), 1);
        assertEq(router2.sent(message), 1);
        assertEq(router3.sent(message), 0);
        assertEq(router1.sent(proof), 0);
        assertEq(router2.sent(proof), 1);
        assertEq(router3.sent(proof), 2);
    }

    function testMessagesCannotBeReplayed(uint8 numRouters, uint8 numParallelDuplicateMessages_, uint256 entropy)
        public
    {
        numRouters = uint8(bound(numRouters, 1, aggregator.MAX_ROUTER_COUNT()));
        uint16 numParallelDuplicateMessages = uint16(bound(numParallelDuplicateMessages_, 1, 255));

        bytes memory message = MessagesLib.formatAddPool(1);
        bytes memory proof = MessagesLib.formatMessageProof(MessagesLib.formatAddPool(1));

        // Setup random set of routers
        address[] memory testRouters = new address[](numRouters);
        for (uint256 i = 0; i < numRouters; i++) {
            testRouters[i] = address(new MockRouter(address(aggregator)));
        }
        aggregator.file("routers", testRouters);

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

    function assertConfirmations(
        bytes memory message,
        uint16 router1Messages,
        uint16 router2Messages,
        uint16 router3Messages,
        uint16 router1Proofs,
        uint16 router2Proofs,
        uint16 router3Proofs
    ) internal {
        (uint16[8] memory messageConfirmations, uint16[8] memory proofConfirmations) =
            aggregator.confirmations(keccak256(message));

        assertEq(messageConfirmations[0], router1Messages);
        assertEq(messageConfirmations[1], router2Messages);
        assertEq(messageConfirmations[2], router3Messages);

        assertEq(proofConfirmations[0], router1Proofs);
        assertEq(proofConfirmations[1], router2Proofs);
        assertEq(proofConfirmations[2], router3Proofs);
    }

    /// @notice Returns the smallest of two numbers.
    function _min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a > b ? b : a;
    }

    function _countValues(uint16[8] memory arr) internal pure returns (uint256 count) {
        for (uint256 i = 0; i < arr.length; ++i) {
            count += arr[i];
        }
    }
}
