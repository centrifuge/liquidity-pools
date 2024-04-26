// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import "test/BaseTest.sol";
import {Aggregator} from "src/gateway/routers/Aggregator.sol";
import {GatewayMock} from "test/mocks/GatewayMock.sol";
import {MockRouter} from "test/mocks/MockRouter.sol";
import {CastLib} from "src/libraries/CastLib.sol";

contract AggregatorTest is Test {
    using CastLib for *;

    Aggregator aggregator;
    GatewayMock gateway;
    MockRouter router1;
    MockRouter router2;
    MockRouter router3;
    MockRouter router4;
    address[] oneMockRouter;
    address[] threeMockRouters;
    address[] fourMockRouters;
    address[] nineMockRouters;

    function setUp() public {
        gateway = new GatewayMock();
        aggregator = new Aggregator(address(gateway));
        aggregator.rely(address(gateway));

        router1 = new MockRouter(address(aggregator));
        vm.label(address(router1), "MockRouter1");
        router2 = new MockRouter(address(aggregator));
        vm.label(address(router2), "MockRouter2");
        router3 = new MockRouter(address(aggregator));
        vm.label(address(router3), "MockRouter3");
        router4 = new MockRouter(address(aggregator));
        vm.label(address(router4), "MockRouter4");

        oneMockRouter.push(address(router1));

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

        vm.expectRevert(bytes("Aggregator/exceeds-max-router-count"));
        aggregator.file("routers", nineMockRouters);

        vm.expectRevert(bytes("Aggregator/file-unrecognized-param"));
        aggregator.file("notRouters", nineMockRouters);

        aggregator.deny(address(this));
        vm.expectRevert(bytes("Auth/not-authorized"));
        aggregator.file("routers", threeMockRouters);
    }

    function testUseBeforeInitialization() public {
        vm.expectRevert(bytes("Aggregator/invalid-router"));
        aggregator.handle(abi.encodePacked(uint8(MessagesLib.Call.AddPool), uint64(1)));

        vm.prank(address(gateway));
        vm.expectRevert(bytes("Aggregator/not-initialized"));
        aggregator.send(abi.encodePacked(uint8(MessagesLib.Call.AddPool), uint64(1)));
    }

    function testIncomingAggregatedMessages() public {
        aggregator.file("routers", threeMockRouters);

        bytes memory firstMessage = abi.encodePacked(uint8(MessagesLib.Call.AddPool), uint64(1));
        bytes memory firstProof = _formatMessageProof(abi.encodePacked(uint8(MessagesLib.Call.AddPool), uint64(1)));

        vm.expectRevert(bytes("Aggregator/invalid-router"));
        aggregator.handle(firstMessage);

        // Executes after quorum is reached
        router1.execute(firstMessage);
        assertEq(gateway.handled(firstMessage), 0);
        assertVotes(firstMessage, 1, 0, 0);

        router2.execute(firstProof);
        assertEq(gateway.handled(firstMessage), 0);
        assertVotes(firstMessage, 1, 1, 0);

        router3.execute(firstProof);
        assertEq(gateway.handled(firstMessage), 1);
        assertVotes(firstMessage, 0, 0, 0);

        // Resending same message works
        router1.execute(firstMessage);
        assertEq(gateway.handled(firstMessage), 1);
        assertVotes(firstMessage, 1, 0, 0);

        router2.execute(firstProof);
        assertEq(gateway.handled(firstMessage), 1);
        assertVotes(firstMessage, 1, 1, 0);

        router3.execute(firstProof);
        assertEq(gateway.handled(firstMessage), 2);
        assertVotes(firstMessage, 0, 0, 0);

        // Sending another message works
        bytes memory secondMessage = abi.encodePacked(uint8(MessagesLib.Call.AddPool), uint64(2));
        bytes memory secondProof = _formatMessageProof(abi.encodePacked(uint8(MessagesLib.Call.AddPool), uint64(2)));

        router1.execute(secondMessage);
        assertEq(gateway.handled(secondMessage), 0);
        assertVotes(secondMessage, 1, 0, 0);

        router2.execute(secondProof);
        assertEq(gateway.handled(secondMessage), 0);
        assertVotes(secondMessage, 1, 1, 0);

        router3.execute(secondProof);
        assertEq(gateway.handled(secondMessage), 1);
        assertVotes(secondMessage, 0, 0, 0);

        // Swapping order of message vs proofs works
        bytes memory thirdMessage = abi.encodePacked(uint8(MessagesLib.Call.AddPool), uint64(3));
        bytes memory thirdProof = _formatMessageProof(abi.encodePacked(uint8(MessagesLib.Call.AddPool), uint64(3)));

        router2.execute(thirdProof);
        assertEq(gateway.handled(thirdMessage), 0);
        assertVotes(thirdMessage, 0, 1, 0);

        router3.execute(thirdProof);
        assertEq(gateway.handled(thirdMessage), 0);
        assertVotes(thirdMessage, 0, 1, 1);

        router1.execute(thirdMessage);
        assertEq(gateway.handled(thirdMessage), 1);
        assertVotes(thirdMessage, 0, 0, 0);
    }

    function testQuorumOfOne() public {
        aggregator.file("routers", oneMockRouter);

        bytes memory message = abi.encodePacked(uint8(MessagesLib.Call.AddPool), uint64(1));

        // Executes immediately
        router1.execute(message);
        assertEq(gateway.handled(message), 1);
    }

    function testOneFasterPayloadRouter() public {
        aggregator.file("routers", threeMockRouters);

        bytes memory message = abi.encodePacked(uint8(MessagesLib.Call.AddPool), uint64(1));
        bytes memory proof = _formatMessageProof(abi.encodePacked(uint8(MessagesLib.Call.AddPool), uint64(1)));

        vm.expectRevert(bytes("Aggregator/invalid-router"));
        aggregator.handle(message);

        // Confirm two messages by payload first
        router1.execute(message);
        router1.execute(message);
        assertEq(gateway.handled(message), 0);
        assertVotes(message, 2, 0, 0);

        // Submit first proof
        router2.execute(proof);
        assertEq(gateway.handled(message), 0);
        assertVotes(message, 2, 1, 0);

        // Submit second proof
        router3.execute(proof);
        assertEq(gateway.handled(message), 1);
        assertVotes(message, 1, 0, 0);

        // Submit third proof
        router2.execute(proof);
        assertEq(gateway.handled(message), 1);
        assertVotes(message, 1, 1, 0);

        // Submit fourth proof
        router3.execute(proof);
        assertEq(gateway.handled(message), 2);
        assertVotes(message, 0, 0, 0);
    }

    function testOutgoingAggregatedMessages() public {
        aggregator.file("routers", threeMockRouters);

        bytes memory message = abi.encodePacked(uint8(MessagesLib.Call.AddPool), uint64(1));
        bytes memory proof = _formatMessageProof(abi.encodePacked(uint8(MessagesLib.Call.AddPool), uint64(1)));

        assertEq(router1.sent(message), 0);
        assertEq(router2.sent(message), 0);
        assertEq(router3.sent(message), 0);
        assertEq(router1.sent(proof), 0);
        assertEq(router2.sent(proof), 0);
        assertEq(router3.sent(proof), 0);

        vm.expectRevert(bytes("Aggregator/only-gateway-allowed-to-call"));
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

        bytes memory message = abi.encodePacked(uint8(MessagesLib.Call.AddPool), uint64(1));
        bytes memory proof = _formatMessageProof(abi.encodePacked(uint8(MessagesLib.Call.AddPool), uint64(1)));

        // Only send through 2 out of 3 routers
        router2.execute(proof);
        router3.execute(proof);
        assertEq(gateway.handled(message), 0);

        vm.expectRevert(bytes("Aggregator/message-recovery-not-initiated"));
        aggregator.executeMessageRecovery(message);

        // Initiate recovery
        router2.execute(
            abi.encodePacked(
                uint8(MessagesLib.Call.InitiateMessageRecovery), keccak256(message), address(router1).toBytes32()
            )
        );

        vm.expectRevert(bytes("Aggregator/challenge-period-has-not-ended"));
        aggregator.executeMessageRecovery(message);

        // Execute recovery
        vm.warp(block.timestamp + aggregator.RECOVERY_CHALLENGE_PERIOD());
        aggregator.executeMessageRecovery(message);
        assertEq(gateway.handled(message), 1);
    }

    function testCannotRecoverWithOneRouter() public {
        aggregator.file("routers", oneMockRouter);

        bytes memory message = abi.encodePacked(uint8(MessagesLib.Call.AddPool), uint64(1));

        vm.expectRevert(bytes("Aggregator/no-recovery-with-one-router-allowed"));
        router1.execute(
            abi.encodePacked(
                uint8(MessagesLib.Call.InitiateMessageRecovery), keccak256(message), address(router1).toBytes32()
            )
        );
    }

    function testRecoverFailedProof() public {
        aggregator.file("routers", threeMockRouters);

        bytes memory message = abi.encodePacked(uint8(MessagesLib.Call.AddPool), uint64(1));
        bytes memory proof = _formatMessageProof(abi.encodePacked(uint8(MessagesLib.Call.AddPool), uint64(1)));

        // Only send through 2 out of 3 routers
        router1.execute(message);
        router2.execute(proof);
        assertEq(gateway.handled(message), 0);

        vm.expectRevert(bytes("Aggregator/message-recovery-not-initiated"));
        aggregator.executeMessageRecovery(proof);

        // Initiate recovery
        router1.execute(
            abi.encodePacked(
                uint8(MessagesLib.Call.InitiateMessageRecovery), keccak256(proof), address(router3).toBytes32()
            )
        );

        vm.expectRevert(bytes("Aggregator/challenge-period-has-not-ended"));
        aggregator.executeMessageRecovery(proof);
        vm.warp(block.timestamp + aggregator.RECOVERY_CHALLENGE_PERIOD());

        aggregator.file("routers", oneMockRouter);
        vm.expectRevert(bytes("Aggregator/invalid-router"));
        aggregator.executeMessageRecovery(proof);
        aggregator.file("routers", threeMockRouters);

        // Execute recovery
        aggregator.executeMessageRecovery(proof);
        assertEq(gateway.handled(message), 1);
    }

    function testDisputeRecovery() public {
        aggregator.file("routers", threeMockRouters);

        bytes memory message = abi.encodePacked(uint8(MessagesLib.Call.AddPool), uint64(1));
        bytes memory proof = _formatMessageProof(abi.encodePacked(uint8(MessagesLib.Call.AddPool), uint64(1)));

        // Only send through 2 out of 3 routers
        router1.execute(message);
        router2.execute(proof);
        assertEq(gateway.handled(message), 0);

        // Initiate recovery
        router1.execute(
            abi.encodePacked(
                uint8(MessagesLib.Call.InitiateMessageRecovery), keccak256(proof), address(router3).toBytes32()
            )
        );

        vm.expectRevert(bytes("Aggregator/challenge-period-has-not-ended"));
        aggregator.executeMessageRecovery(proof);

        // Dispute recovery
        router2.execute(abi.encodePacked(uint8(MessagesLib.Call.DisputeMessageRecovery), keccak256(proof)));

        // Check that recovery is not possible anymore
        vm.expectRevert(bytes("Aggregator/message-recovery-not-initiated"));
        aggregator.executeMessageRecovery(proof);
        assertEq(gateway.handled(message), 0);
    }

    function testRecursiveRecoveryMessageFails() public {
        aggregator.file("routers", threeMockRouters);

        bytes memory message = abi.encodePacked(uint8(MessagesLib.Call.DisputeMessageRecovery), keccak256(""));
        bytes memory proof = _formatMessageProof(abi.encodePacked(uint8(MessagesLib.Call.DisputeMessageRecovery), keccak256("")));

        router2.execute(proof);
        router3.execute(proof);
        assertEq(gateway.handled(message), 0);

        router2.execute(
            abi.encodePacked(
                uint8(MessagesLib.Call.InitiateMessageRecovery), keccak256(message), address(router1).toBytes32()
            )
        );

        vm.warp(block.timestamp + aggregator.RECOVERY_CHALLENGE_PERIOD());

        vm.expectRevert(bytes("Aggregator/no-recursive-recovery-allowed"));
        aggregator.executeMessageRecovery(message);
        assertEq(gateway.handled(message), 0);
    }

    function testMessagesCannotBeReplayed(uint8 numRouters, uint8 numParallelDuplicateMessages_, uint256 entropy)
        public
    {
        numRouters = uint8(bound(numRouters, 1, aggregator.MAX_ROUTER_COUNT()));
        uint16 numParallelDuplicateMessages = uint16(bound(numParallelDuplicateMessages_, 1, 255));

        bytes memory message = abi.encodePacked(uint8(MessagesLib.Call.AddPool), uint64(1));
        bytes memory proof = _formatMessageProof(abi.encodePacked(uint8(MessagesLib.Call.AddPool), uint64(1)));

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

    function assertVotes(bytes memory message, uint16 r1, uint16 r2, uint16 r3) internal {
        uint16[8] memory votes = aggregator.votes(keccak256(message));
        assertEq(votes[0], r1);
        assertEq(votes[1], r2);
        assertEq(votes[2], r3);
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

    function _formatMessageProof(bytes memory message) internal pure returns (bytes memory) {
        return abi.encodePacked(uint8(MessagesLib.Call.MessageProof), keccak256(message));
    }

    function _formatMessageProof(bytes32 messageHash) internal pure returns (bytes memory) {
        return abi.encodePacked(uint8(MessagesLib.Call.MessageProof), messageHash);
    }
}
