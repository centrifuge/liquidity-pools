// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import "test/BaseTest.sol";
import {MockGateway} from "test/mocks/MockGateway.sol";
import {MockRouter} from "test/mocks/MockRouter.sol";
import {MockRoot} from "test/mocks/MockRoot.sol";
import {MockManager} from "test/mocks/MockManager.sol";
import {MockAxelarGasService} from "test/mocks/MockAxelarGasService.sol";
import {CastLib} from "src/libraries/CastLib.sol";

contract GatewayExtensionTest is Test {
    using CastLib for *;

    MockRoot root;
    MockManager investmentManager;
    MockManager poolManager;
    MockGasService gasService;
    MockRouter router1;
    MockRouter router2;
    MockRouter router3;
    MockRouter router4;
    address[] oneMockRouter;
    address[] twoDuplicateMockRouters;
    address[] threeMockRouters;
    address[] fourMockRouters;
    address[] nineMockRouters;
    Gateway gateway;

    function setUp() public {
        root = new MockRoot();
        investmentManager = new MockManager();
        poolManager = new MockManager();
        gasService = new MockGasService();
        gateway = new Gateway(address(root), address(investmentManager), address(poolManager), address(gasService));

        gasService.setReturn("shouldRefuel", true);
        vm.deal(address(gateway), 1 ether);


        router1 = new MockRouter(address(gateway));
        vm.label(address(router1), "MockRouter1");
        router2 = new MockRouter(address(gateway));
        vm.label(address(router2), "MockRouter2");
        router3 = new MockRouter(address(gateway));
        vm.label(address(router3), "MockRouter3");
        router4 = new MockRouter(address(gateway));
        vm.label(address(router4), "MockRouter4");

        oneMockRouter.push(address(router1));

        threeMockRouters.push(address(router1));
        threeMockRouters.push(address(router2));
        threeMockRouters.push(address(router3));

        twoDuplicateMockRouters.push(address(router1));
        twoDuplicateMockRouters.push(address(router1));

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
        gateway.file("routers", threeMockRouters);
        assertEq(gateway.routers(0), address(router1));
        assertEq(gateway.routers(1), address(router2));
        assertEq(gateway.routers(2), address(router3));
        assertEq(gateway.activeSessionId(), 0);

        vm.expectRevert(bytes(""));
        assertEq(gateway.routers(3), address(0));

        (uint8 validRouter1Id, uint8 validRouter1Quorum,) = gateway.activeRouters(address(router1));
        assertEq(validRouter1Id, 1);
        assertEq(validRouter1Quorum, 3);
        (uint8 validRouter2Id, uint8 validRouter2Quorum,) = gateway.activeRouters(address(router2));
        assertEq(validRouter2Id, 2);
        assertEq(validRouter2Quorum, 3);
        (uint8 validRouter3Id, uint8 validRouter3Quorum,) = gateway.activeRouters(address(router3));
        assertEq(validRouter3Id, 3);
        assertEq(validRouter3Quorum, 3);
        (uint8 invalidRouter4Id, uint8 invalidRouter4Quorum,) = gateway.activeRouters(address(router4));
        assertEq(invalidRouter4Id, 0);
        assertEq(invalidRouter4Quorum, 0);

        gateway.file("routers", fourMockRouters);
        (uint8 validRouter4Id, uint8 validRouter4Quorum,) = gateway.activeRouters(address(router4));
        assertEq(validRouter4Id, 4);
        assertEq(validRouter4Quorum, 4);
        assertEq(gateway.routers(3), address(router4));
        assertEq(gateway.activeSessionId(), 0);

        gateway.file("routers", threeMockRouters);
        (invalidRouter4Id, invalidRouter4Quorum,) = gateway.activeRouters(address(router4));
        assertEq(invalidRouter4Id, 0);
        assertEq(invalidRouter4Quorum, 0);
        assertEq(gateway.activeSessionId(), 1);
        vm.expectRevert(bytes(""));
        assertEq(gateway.routers(3), address(0));

        vm.expectRevert(bytes("Gateway/exceeds-max-router-count"));
        gateway.file("routers", nineMockRouters);

        vm.expectRevert(bytes("Gateway/file-unrecognized-param"));
        gateway.file("notRouters", nineMockRouters);

        vm.expectRevert(bytes("Gateway/no-duplicates-allowed"));
        gateway.file("routers", twoDuplicateMockRouters);

        gateway.deny(address(this));
        vm.expectRevert(bytes("Auth/not-authorized"));
        gateway.file("routers", threeMockRouters);
    }

    function testUseBeforeInitialization() public {
        vm.expectRevert(bytes("Gateway/invalid-router"));
        gateway.handle(abi.encodePacked(uint8(MessagesLib.Call.AddPool), uint64(1)));

        vm.expectRevert(bytes("Gateway/invalid-manager"));
        gateway.send(abi.encodePacked(uint8(MessagesLib.Call.AddPool), uint64(1)), address(this));
    }

    function testIncomingAggregatedMessages() public {
        gateway.file("routers", threeMockRouters);

        bytes memory firstMessage = abi.encodePacked(uint8(MessagesLib.Call.AddPool), uint64(1));
        bytes memory firstProof = _formatMessageProof(abi.encodePacked(uint8(MessagesLib.Call.AddPool), uint64(1)));

        vm.expectRevert(bytes("Gateway/invalid-router"));
        gateway.handle(firstMessage);

        // Executes after quorum is reached
        _send(router1, firstMessage);
        assertEq(poolManager.received(firstMessage), 0);
        assertVotes(firstMessage, 1, 0, 0);

        _send(router2, firstProof);
        assertEq(poolManager.received(firstMessage), 0);
        assertVotes(firstMessage, 1, 1, 0);

        _send(router3, firstProof);
        assertEq(poolManager.received(firstMessage), 1);
        assertVotes(firstMessage, 0, 0, 0);

        // Resending same message works
        _send(router1, firstMessage);
        assertEq(poolManager.received(firstMessage), 1);
        assertVotes(firstMessage, 1, 0, 0);

        _send(router2, firstProof);
        assertEq(poolManager.received(firstMessage), 1);
        assertVotes(firstMessage, 1, 1, 0);

        _send(router3, firstProof);
        assertEq(poolManager.received(firstMessage), 2);
        assertVotes(firstMessage, 0, 0, 0);

        // Sending another message works
        bytes memory secondMessage = abi.encodePacked(uint8(MessagesLib.Call.AddPool), uint64(2));
        bytes memory secondProof = _formatMessageProof(abi.encodePacked(uint8(MessagesLib.Call.AddPool), uint64(2)));

        _send(router1, secondMessage);
        assertEq(poolManager.received(secondMessage), 0);
        assertVotes(secondMessage, 1, 0, 0);

        _send(router2, secondProof);
        assertEq(poolManager.received(secondMessage), 0);
        assertVotes(secondMessage, 1, 1, 0);

        _send(router3, secondProof);
        assertEq(poolManager.received(secondMessage), 1);
        assertVotes(secondMessage, 0, 0, 0);

        // Swapping order of message vs proofs works
        bytes memory thirdMessage = abi.encodePacked(uint8(MessagesLib.Call.AddPool), uint64(3));
        bytes memory thirdProof = _formatMessageProof(abi.encodePacked(uint8(MessagesLib.Call.AddPool), uint64(3)));

        _send(router2, thirdProof);
        assertEq(poolManager.received(thirdMessage), 0);
        assertVotes(thirdMessage, 0, 1, 0);

        _send(router3, thirdProof);
        assertEq(poolManager.received(thirdMessage), 0);
        assertVotes(thirdMessage, 0, 1, 1);

        _send(router1, thirdMessage);
        assertEq(poolManager.received(thirdMessage), 1);
        assertVotes(thirdMessage, 0, 0, 0);
    }

    function testQuorumOfOne() public {
        gateway.file("routers", oneMockRouter);

        bytes memory message = abi.encodePacked(uint8(MessagesLib.Call.AddPool), uint64(1));

        // Executes immediately
        _send(router1, message);
        assertEq(poolManager.received(message), 1);
    }

    function testOneFasterPayloadRouter() public {
        gateway.file("routers", threeMockRouters);

        bytes memory message = abi.encodePacked(uint8(MessagesLib.Call.AddPool), uint64(1));
        bytes memory proof = _formatMessageProof(abi.encodePacked(uint8(MessagesLib.Call.AddPool), uint64(1)));

        vm.expectRevert(bytes("Gateway/invalid-router"));
        gateway.handle(message);

        // Confirm two messages by payload first
        _send(router1, message);
        _send(router1, message);
        assertEq(poolManager.received(message), 0);
        assertVotes(message, 2, 0, 0);

        // Submit first proof
        _send(router2, proof);
        assertEq(poolManager.received(message), 0);
        assertVotes(message, 2, 1, 0);

        // Submit second proof
        _send(router3, proof);
        assertEq(poolManager.received(message), 1);
        assertVotes(message, 1, 0, 0);

        // Submit third proof
        _send(router2, proof);
        assertEq(poolManager.received(message), 1);
        assertVotes(message, 1, 1, 0);

        // Submit fourth proof
        _send(router3, proof);
        assertEq(poolManager.received(message), 2);
        assertVotes(message, 0, 0, 0);
    }

    function testVotesExpireAfterSession() public {
        gateway.file("routers", fourMockRouters);

        bytes memory message = abi.encodePacked(uint8(MessagesLib.Call.AddPool), uint64(1));
        bytes memory proof = _formatMessageProof(abi.encodePacked(uint8(MessagesLib.Call.AddPool), uint64(1)));

        _send(router1, message);
        _send(router2, proof);
        assertEq(investmentManager.received(message), 0);
        assertVotes(message, 1, 1, 0);

        gateway.file("routers", threeMockRouters);

        router3.execute(proof);
        assertEq(investmentManager.received(message), 0);
        assertVotes(message, 0, 0, 1);
    }

    function testOutgoingAggregatedMessages() public {
        gateway.file("routers", threeMockRouters);

        bytes memory message = abi.encodePacked(uint8(MessagesLib.Call.AddPool), uint64(1));
        bytes memory proof = _formatMessageProof(abi.encodePacked(uint8(MessagesLib.Call.AddPool), uint64(1)));

        assertEq(router1.sent(message), 0);
        assertEq(router2.sent(message), 0);
        assertEq(router3.sent(message), 0);
        assertEq(router1.sent(proof), 0);
        assertEq(router2.sent(proof), 0);
        assertEq(router3.sent(proof), 0);
        vm.expectRevert(bytes("Gateway/invalid-manager"));
        gateway.send(message, address(this));

        vm.prank(address(investmentManager));
        gateway.send(message, address(this));

        assertEq(router1.sent(message), 1);
        assertEq(router2.sent(message), 0);
        assertEq(router3.sent(message), 0);
        assertEq(router1.sent(proof), 0);
        assertEq(router2.sent(proof), 1);
        assertEq(router3.sent(proof), 1);
    }

    function testRecoverFailedMessage() public {
        gateway.file("routers", threeMockRouters);

        bytes memory message = abi.encodePacked(uint8(MessagesLib.Call.AddPool), uint64(1));
        bytes memory proof = _formatMessageProof(abi.encodePacked(uint8(MessagesLib.Call.AddPool), uint64(1)));

        // Only send through 2 out of 3 routers
        router2.execute(proof);
        router3.execute(proof);
        assertEq(poolManager.received(message), 0);

        vm.expectRevert(bytes("Gateway/message-recovery-not-initiated"));
        gateway.executeMessageRecovery(message);

        // Initiate recovery
        _send(
            router2,
            abi.encodePacked(
                uint8(MessagesLib.Call.InitiateMessageRecovery), keccak256(message), address(router1).toBytes32()
            )
        );

        vm.expectRevert(bytes("Gateway/challenge-period-has-not-ended"));
        gateway.executeMessageRecovery(message);

        // Execute recovery
        vm.warp(block.timestamp + gateway.RECOVERY_CHALLENGE_PERIOD());
        gateway.executeMessageRecovery(message);
        assertEq(poolManager.received(message), 1);
    }

    function testCannotRecoverWithOneRouter() public {
        gateway.file("routers", oneMockRouter);

        bytes memory message = abi.encodePacked(uint8(MessagesLib.Call.AddPool), uint64(1));

        vm.expectRevert(bytes("Gateway/no-recovery-with-one-router-allowed"));
        _send(
            router1,
            abi.encodePacked(
                uint8(MessagesLib.Call.InitiateMessageRecovery), keccak256(message), address(router1).toBytes32()
            )
        );
    }

    function testRecoverFailedProof() public {
        gateway.file("routers", threeMockRouters);

        bytes memory message = abi.encodePacked(uint8(MessagesLib.Call.AddPool), uint64(1));
        bytes memory proof = _formatMessageProof(abi.encodePacked(uint8(MessagesLib.Call.AddPool), uint64(1)));

        // Only send through 2 out of 3 routers
        router1.execute(message);
        router2.execute(proof);
        _send(router1, message);
        _send(router2, proof);
        assertEq(investmentManager.received(message), 0);

        vm.expectRevert(bytes("Gateway/message-recovery-not-initiated"));
        gateway.executeMessageRecovery(proof);

        // Initiate recovery
        _send(
            router1,
            abi.encodePacked(
                uint8(MessagesLib.Call.InitiateMessageRecovery), keccak256(proof), address(router3).toBytes32()
            )
        );

        vm.expectRevert(bytes("Gateway/challenge-period-has-not-ended"));
        gateway.executeMessageRecovery(proof);
        vm.warp(block.timestamp + gateway.RECOVERY_CHALLENGE_PERIOD());

        // Execute recovery
        gateway.executeMessageRecovery(proof);
        assertEq(poolManager.received(message), 1);
    }

    function testCannotRecoverInvalidRouter() public {
        gateway.file("routers", threeMockRouters);

        bytes memory message = abi.encodePacked(uint8(MessagesLib.Call.AddPool), uint64(1));
        bytes memory proof = _formatMessageProof(abi.encodePacked(uint8(MessagesLib.Call.AddPool), uint64(1)));

        // Only send through 2 out of 3 routers
        _send(router1, message);
        _send(router2, proof);
        assertEq(poolManager.received(message), 0);

        // Initiate recovery
        _send(
            router1,
            abi.encodePacked(
                uint8(MessagesLib.Call.InitiateMessageRecovery), keccak256(proof), address(router3).toBytes32()
            )
        );

        vm.warp(block.timestamp + gateway.RECOVERY_CHALLENGE_PERIOD());

        gateway.file("routers", oneMockRouter);
        vm.expectRevert(bytes("Gateway/invalid-router"));
        gateway.executeMessageRecovery(proof);
        gateway.file("routers", threeMockRouters);
    }

    function testDisputeRecovery() public {
        gateway.file("routers", threeMockRouters);

        bytes memory message = abi.encodePacked(uint8(MessagesLib.Call.AddPool), uint64(1));
        bytes memory proof = _formatMessageProof(abi.encodePacked(uint8(MessagesLib.Call.AddPool), uint64(1)));

        // Only send through 2 out of 3 routers
        _send(router1, message);
        _send(router2, proof);
        assertEq(poolManager.received(message), 0);

        // Initiate recovery
        _send(
            router1,
            abi.encodePacked(
                uint8(MessagesLib.Call.InitiateMessageRecovery), keccak256(proof), address(router3).toBytes32()
            )
        );

        vm.expectRevert(bytes("Gateway/challenge-period-has-not-ended"));
        gateway.executeMessageRecovery(proof);

        // Dispute recovery
        _send(
            router2,
            abi.encodePacked(
                uint8(MessagesLib.Call.DisputeMessageRecovery), keccak256(proof), address(router3).toBytes32()
            )
        );

        // Check that recovery is not possible anymore
        vm.expectRevert(bytes("Gateway/message-recovery-not-initiated"));
        gateway.executeMessageRecovery(proof);
        assertEq(poolManager.received(message), 0);
    }

    function testRecursiveRecoveryMessageFails() public {
        gateway.file("routers", threeMockRouters);

        bytes memory message = abi.encodePacked(uint8(MessagesLib.Call.DisputeMessageRecovery), keccak256(""));
        bytes memory proof =
            _formatMessageProof(abi.encodePacked(uint8(MessagesLib.Call.DisputeMessageRecovery), keccak256("")));

        _send(router2, proof);
        _send(router3, proof);
        assertEq(poolManager.received(message), 0);

        _send(
            router2,
            abi.encodePacked(
                uint8(MessagesLib.Call.InitiateMessageRecovery), keccak256(message), address(router1).toBytes32()
            )
        );

        vm.warp(block.timestamp + gateway.RECOVERY_CHALLENGE_PERIOD());

        vm.expectRevert(bytes("Gateway/no-recursive-recovery-allowed"));
        gateway.executeMessageRecovery(message);
        assertEq(poolManager.received(message), 0);
    }

    function testMessagesCannotBeReplayed(uint8 numRouters, uint8 numParallelDuplicateMessages_, uint256 entropy)
        public
    {
        numRouters = uint8(bound(numRouters, 1, gateway.MAX_ROUTER_COUNT()));
        uint16 numParallelDuplicateMessages = uint16(bound(numParallelDuplicateMessages_, 1, 255));

        bytes memory message = abi.encodePacked(uint8(MessagesLib.Call.AddPool), uint64(1));
        bytes memory proof = _formatMessageProof(abi.encodePacked(uint8(MessagesLib.Call.AddPool), uint64(1)));

        // Setup random set of routers
        address[] memory testRouters = new address[](numRouters);
        for (uint256 i = 0; i < numRouters; i++) {
            testRouters[i] = address(new MockRouter(address(gateway)));
        }
        gateway.file("routers", testRouters);

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
                _send(MockRouter(testRouters[randomRouterId]), message);
            } else {
                _send(MockRouter(testRouters[randomRouterId]), proof);
            }

            totalSent++;
            sentPerRouter[randomRouterId]++;
        }

        // Check that each message was confirmed exactly numParallelDuplicateMessages times
        for (uint256 j = 0; j < numParallelDuplicateMessages; j++) {
            assertEq(poolManager.received(message), numParallelDuplicateMessages);
        }
    }

    function assertVotes(bytes memory message, uint16 r1, uint16 r2, uint16 r3) internal {
        uint16[8] memory votes = gateway.votes(keccak256(message));
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

    function _send(MockRouter router, bytes memory message) internal {
        vm.prank(address(router));
        gateway.handle(message);
    }
}
