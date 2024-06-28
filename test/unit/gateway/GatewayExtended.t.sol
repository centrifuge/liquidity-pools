// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import "test/BaseTest.sol";
import {MockGateway} from "test/mocks/MockGateway.sol";
import {MockAdapter} from "test/mocks/MockAdapter.sol";
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
    MockAdapter adapter1;

    MockAdapter adapter2;

    MockAdapter adapter3;
    MockAdapter adapter4;
    address[] oneMockAdapter;
    address[] twoDuplicateMockAdapters;
    address[] threeMockAdapters;
    address[] fourMockAdapters;
    address[] nineMockAdapters;
    Gateway gateway;

    function setUp() public {
        root = new MockRoot();
        investmentManager = new MockManager();
        poolManager = new MockManager();
        gasService = new MockGasService();
        gateway = new Gateway(address(root), address(investmentManager), address(poolManager), address(gasService));

        gasService.setReturn("shouldRefuel", true);
        vm.deal(address(gateway), 1 ether);

        adapter1 = new MockAdapter(address(gateway));
        vm.label(address(adapter1), "MockAdapter1");
        adapter2 = new MockAdapter(address(gateway));
        vm.label(address(adapter2), "MockAdapter2");
        adapter3 = new MockAdapter(address(gateway));
        vm.label(address(adapter3), "MockAdapter3");
        adapter4 = new MockAdapter(address(gateway));
        vm.label(address(adapter4), "MockAdapter4");

        oneMockAdapter.push(address(adapter1));

        threeMockAdapters.push(address(adapter1));
        threeMockAdapters.push(address(adapter2));
        threeMockAdapters.push(address(adapter3));

        twoDuplicateMockAdapters.push(address(adapter1));
        twoDuplicateMockAdapters.push(address(adapter1));

        fourMockAdapters.push(address(adapter1));
        fourMockAdapters.push(address(adapter2));
        fourMockAdapters.push(address(adapter3));
        fourMockAdapters.push(address(adapter4));

        nineMockAdapters.push(address(adapter1));
        nineMockAdapters.push(address(adapter1));
        nineMockAdapters.push(address(adapter1));
        nineMockAdapters.push(address(adapter1));
        nineMockAdapters.push(address(adapter1));
        nineMockAdapters.push(address(adapter1));
        nineMockAdapters.push(address(adapter1));
        nineMockAdapters.push(address(adapter1));
        nineMockAdapters.push(address(adapter1));
    }

    function testFileAdapters() public {
        gateway.file("adapters", threeMockAdapters);
        assertEq(gateway.adapters(0), address(adapter1));
        assertEq(gateway.adapters(1), address(adapter2));
        assertEq(gateway.adapters(2), address(adapter3));
        assertEq(gateway.activeSessionId(), 0);

        vm.expectRevert(bytes(""));
        assertEq(gateway.adapters(3), address(0));

        (uint8 validAdapter1Id, uint8 validAdapter1Quorum,) = gateway.activeAdapters(address(adapter1));
        assertEq(validAdapter1Id, 1);
        assertEq(validAdapter1Quorum, 3);
        (uint8 validAdapter2Id, uint8 validAdapter2Quorum,) = gateway.activeAdapters(address(adapter2));
        assertEq(validAdapter2Id, 2);
        assertEq(validAdapter2Quorum, 3);
        (uint8 validAdapter3Id, uint8 validAdapter3Quorum,) = gateway.activeAdapters(address(adapter3));
        assertEq(validAdapter3Id, 3);
        assertEq(validAdapter3Quorum, 3);
        (uint8 invalidAdapter4Id, uint8 invalidAdapter4Quorum,) = gateway.activeAdapters(address(adapter4));
        assertEq(invalidAdapter4Id, 0);
        assertEq(invalidAdapter4Quorum, 0);

        gateway.file("adapters", fourMockAdapters);
        (uint8 validAdapter4Id, uint8 validAdapter4Quorum,) = gateway.activeAdapters(address(adapter4));
        assertEq(validAdapter4Id, 4);
        assertEq(validAdapter4Quorum, 4);
        assertEq(gateway.adapters(3), address(adapter4));
        assertEq(gateway.activeSessionId(), 0);

        gateway.file("adapters", threeMockAdapters);
        (invalidAdapter4Id, invalidAdapter4Quorum,) = gateway.activeAdapters(address(adapter4));
        assertEq(invalidAdapter4Id, 0);
        assertEq(invalidAdapter4Quorum, 0);
        assertEq(gateway.activeSessionId(), 1);
        vm.expectRevert(bytes(""));
        assertEq(gateway.adapters(3), address(0));

        vm.expectRevert(bytes("Gateway/exceeds-max-adapter-count"));
        gateway.file("adapters", nineMockAdapters);

        vm.expectRevert(bytes("Gateway/file-unrecognized-param"));
        gateway.file("notAdapters", nineMockAdapters);

        vm.expectRevert(bytes("Gateway/no-duplicates-allowed"));
        gateway.file("adapters", twoDuplicateMockAdapters);

        gateway.deny(address(this));
        vm.expectRevert(bytes("Auth/not-authorized"));
        gateway.file("adapters", threeMockAdapters);
    }

    function testUseBeforeInitialization() public {
        vm.expectRevert(bytes("Gateway/invalid-adapter"));
        gateway.handle(abi.encodePacked(uint8(MessagesLib.Call.AddPool), uint64(1)));

        vm.expectRevert(bytes("Gateway/invalid-manager"));
        gateway.send(abi.encodePacked(uint8(MessagesLib.Call.AddPool), uint64(1)), address(this));
    }

    function testIncomingAggregatedMessages() public {
        gateway.file("adapters", threeMockAdapters);

        bytes memory firstMessage = abi.encodePacked(uint8(MessagesLib.Call.AddPool), uint64(1));
        bytes memory firstProof = _formatMessageProof(abi.encodePacked(uint8(MessagesLib.Call.AddPool), uint64(1)));

        vm.expectRevert(bytes("Gateway/invalid-adapter"));
        gateway.handle(firstMessage);

        // Executes after quorum is reached
        _send(adapter1, firstMessage);
        assertEq(poolManager.received(firstMessage), 0);
        assertVotes(firstMessage, 1, 0, 0);

        _send(adapter2, firstProof);
        assertEq(poolManager.received(firstMessage), 0);
        assertVotes(firstMessage, 1, 1, 0);

        _send(adapter3, firstProof);
        assertEq(poolManager.received(firstMessage), 1);
        assertVotes(firstMessage, 0, 0, 0);

        // Resending same message works
        _send(adapter1, firstMessage);
        assertEq(poolManager.received(firstMessage), 1);
        assertVotes(firstMessage, 1, 0, 0);

        _send(adapter2, firstProof);
        assertEq(poolManager.received(firstMessage), 1);
        assertVotes(firstMessage, 1, 1, 0);

        _send(adapter3, firstProof);
        assertEq(poolManager.received(firstMessage), 2);
        assertVotes(firstMessage, 0, 0, 0);

        // Sending another message works
        bytes memory secondMessage = abi.encodePacked(uint8(MessagesLib.Call.AddPool), uint64(2));
        bytes memory secondProof = _formatMessageProof(abi.encodePacked(uint8(MessagesLib.Call.AddPool), uint64(2)));

        _send(adapter1, secondMessage);
        assertEq(poolManager.received(secondMessage), 0);
        assertVotes(secondMessage, 1, 0, 0);

        _send(adapter2, secondProof);
        assertEq(poolManager.received(secondMessage), 0);
        assertVotes(secondMessage, 1, 1, 0);

        _send(adapter3, secondProof);
        assertEq(poolManager.received(secondMessage), 1);
        assertVotes(secondMessage, 0, 0, 0);

        // Swapping order of message vs proofs works
        bytes memory thirdMessage = abi.encodePacked(uint8(MessagesLib.Call.AddPool), uint64(3));
        bytes memory thirdProof = _formatMessageProof(abi.encodePacked(uint8(MessagesLib.Call.AddPool), uint64(3)));

        _send(adapter2, thirdProof);
        assertEq(poolManager.received(thirdMessage), 0);
        assertVotes(thirdMessage, 0, 1, 0);

        _send(adapter3, thirdProof);
        assertEq(poolManager.received(thirdMessage), 0);
        assertVotes(thirdMessage, 0, 1, 1);

        _send(adapter1, thirdMessage);
        assertEq(poolManager.received(thirdMessage), 1);
        assertVotes(thirdMessage, 0, 0, 0);
    }

    function testQuorumOfOne() public {
        gateway.file("adapters", oneMockAdapter);

        bytes memory message = abi.encodePacked(uint8(MessagesLib.Call.AddPool), uint64(1));

        // Executes immediately
        _send(adapter1, message);
        assertEq(poolManager.received(message), 1);
    }

    function testOneFasterPayloadAdapter() public {
        gateway.file("adapters", threeMockAdapters);

        bytes memory message = abi.encodePacked(uint8(MessagesLib.Call.AddPool), uint64(1));
        bytes memory proof = _formatMessageProof(abi.encodePacked(uint8(MessagesLib.Call.AddPool), uint64(1)));

        vm.expectRevert(bytes("Gateway/invalid-adapter"));
        gateway.handle(message);

        // Confirm two messages by payload first
        _send(adapter1, message);
        _send(adapter1, message);
        assertEq(poolManager.received(message), 0);
        assertVotes(message, 2, 0, 0);

        // Submit first proof
        _send(adapter2, proof);
        assertEq(poolManager.received(message), 0);
        assertVotes(message, 2, 1, 0);

        // Submit second proof
        _send(adapter3, proof);
        assertEq(poolManager.received(message), 1);
        assertVotes(message, 1, 0, 0);

        // Submit third proof
        _send(adapter2, proof);
        assertEq(poolManager.received(message), 1);
        assertVotes(message, 1, 1, 0);

        // Submit fourth proof
        _send(adapter3, proof);
        assertEq(poolManager.received(message), 2);
        assertVotes(message, 0, 0, 0);
    }

    function testVotesExpireAfterSession() public {
        gateway.file("adapters", fourMockAdapters);

        bytes memory message = abi.encodePacked(uint8(MessagesLib.Call.AddPool), uint64(1));
        bytes memory proof = _formatMessageProof(abi.encodePacked(uint8(MessagesLib.Call.AddPool), uint64(1)));

        _send(adapter1, message);
        _send(adapter2, proof);
        assertEq(investmentManager.received(message), 0);
        assertVotes(message, 1, 1, 0);

        gateway.file("adapters", threeMockAdapters);

        adapter3.execute(proof);
        assertEq(investmentManager.received(message), 0);
        assertVotes(message, 0, 0, 1);
    }

    function testOutgoingAggregatedMessages() public {
        gateway.file("adapters", threeMockAdapters);

        bytes memory message = abi.encodePacked(uint8(MessagesLib.Call.AddPool), uint64(1));
        bytes memory proof = _formatMessageProof(abi.encodePacked(uint8(MessagesLib.Call.AddPool), uint64(1)));

        assertEq(adapter1.sent(message), 0);
        assertEq(adapter2.sent(message), 0);
        assertEq(adapter3.sent(message), 0);
        assertEq(adapter1.sent(proof), 0);
        assertEq(adapter2.sent(proof), 0);
        assertEq(adapter3.sent(proof), 0);
        vm.expectRevert(bytes("Gateway/invalid-manager"));
        gateway.send(message, address(this));

        vm.prank(address(investmentManager));
        gateway.send(message, address(this));

        assertEq(adapter1.sent(message), 1);
        assertEq(adapter2.sent(message), 0);
        assertEq(adapter3.sent(message), 0);
        assertEq(adapter1.sent(proof), 0);
        assertEq(adapter2.sent(proof), 1);
        assertEq(adapter3.sent(proof), 1);
    }

    function testRecoverFailedMessage() public {
        gateway.file("adapters", threeMockAdapters);

        bytes memory message = abi.encodePacked(uint8(MessagesLib.Call.AddPool), uint64(1));
        bytes memory proof = _formatMessageProof(abi.encodePacked(uint8(MessagesLib.Call.AddPool), uint64(1)));

        // Only send through 2 out of 3 adapters
        adapter2.execute(proof);
        adapter3.execute(proof);
        assertEq(poolManager.received(message), 0);

        vm.expectRevert(bytes("Gateway/message-recovery-not-initiated"));
        gateway.executeMessageRecovery(message);

        // Initiate recovery
        _send(
            adapter2,
            abi.encodePacked(
                uint8(MessagesLib.Call.InitiateMessageRecovery), keccak256(message), address(adapter1).toBytes32()
            )
        );

        vm.expectRevert(bytes("Gateway/challenge-period-has-not-ended"));
        gateway.executeMessageRecovery(message);

        // Execute recovery
        vm.warp(block.timestamp + gateway.RECOVERY_CHALLENGE_PERIOD());
        gateway.executeMessageRecovery(message);
        assertEq(poolManager.received(message), 1);
    }

    function testCannotRecoverWithOneAdapter() public {
        gateway.file("adapters", oneMockAdapter);

        bytes memory message = abi.encodePacked(uint8(MessagesLib.Call.AddPool), uint64(1));

        vm.expectRevert(bytes("Gateway/no-recovery-with-one-adapter-allowed"));
        _send(
            adapter1,
            abi.encodePacked(
                uint8(MessagesLib.Call.InitiateMessageRecovery), keccak256(message), address(adapter1).toBytes32()
            )
        );
    }

    function testRecoverFailedProof() public {
        gateway.file("adapters", threeMockAdapters);

        bytes memory message = abi.encodePacked(uint8(MessagesLib.Call.AddPool), uint64(1));
        bytes memory proof = _formatMessageProof(abi.encodePacked(uint8(MessagesLib.Call.AddPool), uint64(1)));

        // Only send through 2 out of 3 adapters
        adapter1.execute(message);
        adapter2.execute(proof);
        _send(adapter1, message);
        _send(adapter2, proof);
        assertEq(investmentManager.received(message), 0);

        vm.expectRevert(bytes("Gateway/message-recovery-not-initiated"));
        gateway.executeMessageRecovery(proof);

        // Initiate recovery
        _send(
            adapter1,
            abi.encodePacked(
                uint8(MessagesLib.Call.InitiateMessageRecovery), keccak256(proof), address(adapter3).toBytes32()
            )
        );

        vm.expectRevert(bytes("Gateway/challenge-period-has-not-ended"));
        gateway.executeMessageRecovery(proof);
        vm.warp(block.timestamp + gateway.RECOVERY_CHALLENGE_PERIOD());

        // Execute recovery
        gateway.executeMessageRecovery(proof);
        assertEq(poolManager.received(message), 1);
    }

    function testCannotRecoverInvalidAdapter() public {
        gateway.file("adapters", threeMockAdapters);

        bytes memory message = abi.encodePacked(uint8(MessagesLib.Call.AddPool), uint64(1));
        bytes memory proof = _formatMessageProof(abi.encodePacked(uint8(MessagesLib.Call.AddPool), uint64(1)));

        // Only send through 2 out of 3 adapters
        _send(adapter1, message);
        _send(adapter2, proof);
        assertEq(poolManager.received(message), 0);

        // Initiate recovery
        _send(
            adapter1,
            abi.encodePacked(
                uint8(MessagesLib.Call.InitiateMessageRecovery), keccak256(proof), address(adapter3).toBytes32()
            )
        );

        vm.warp(block.timestamp + gateway.RECOVERY_CHALLENGE_PERIOD());

        gateway.file("adapters", oneMockAdapter);
        vm.expectRevert(bytes("Gateway/invalid-adapter"));
        gateway.executeMessageRecovery(proof);
        gateway.file("adapters", threeMockAdapters);
    }

    function testDisputeRecovery() public {
        gateway.file("adapters", threeMockAdapters);

        bytes memory message = abi.encodePacked(uint8(MessagesLib.Call.AddPool), uint64(1));
        bytes memory proof = _formatMessageProof(abi.encodePacked(uint8(MessagesLib.Call.AddPool), uint64(1)));

        // Only send through 2 out of 3 adapters
        _send(adapter1, message);
        _send(adapter2, proof);
        assertEq(poolManager.received(message), 0);

        // Initiate recovery
        _send(
            adapter1,
            abi.encodePacked(
                uint8(MessagesLib.Call.InitiateMessageRecovery), keccak256(proof), address(adapter3).toBytes32()
            )
        );

        vm.expectRevert(bytes("Gateway/challenge-period-has-not-ended"));
        gateway.executeMessageRecovery(proof);

        // Dispute recovery
        _send(
            adapter2,
            abi.encodePacked(
                uint8(MessagesLib.Call.DisputeMessageRecovery), keccak256(proof), address(adapter3).toBytes32()
            )
        );

        // Check that recovery is not possible anymore
        vm.expectRevert(bytes("Gateway/message-recovery-not-initiated"));
        gateway.executeMessageRecovery(proof);
        assertEq(poolManager.received(message), 0);
    }

    function testRecursiveRecoveryMessageFails() public {
        gateway.file("adapters", threeMockAdapters);

        bytes memory message = abi.encodePacked(uint8(MessagesLib.Call.DisputeMessageRecovery), keccak256(""));
        bytes memory proof =
            _formatMessageProof(abi.encodePacked(uint8(MessagesLib.Call.DisputeMessageRecovery), keccak256("")));

        _send(adapter2, proof);
        _send(adapter3, proof);
        assertEq(poolManager.received(message), 0);

        _send(
            adapter2,
            abi.encodePacked(
                uint8(MessagesLib.Call.InitiateMessageRecovery), keccak256(message), address(adapter1).toBytes32()
            )
        );

        vm.warp(block.timestamp + gateway.RECOVERY_CHALLENGE_PERIOD());

        vm.expectRevert(bytes("Gateway/no-recursive-recovery-allowed"));
        gateway.executeMessageRecovery(message);
        assertEq(poolManager.received(message), 0);
    }

    function testMessagesCannotBeReplayed(uint8 numAdapters, uint8 numParallelDuplicateMessages_, uint256 entropy)
        public
    {
        numAdapters = uint8(bound(numAdapters, 1, gateway.MAX_ADAPTER_COUNT()));
        uint16 numParallelDuplicateMessages = uint16(bound(numParallelDuplicateMessages_, 1, 255));

        bytes memory message = abi.encodePacked(uint8(MessagesLib.Call.AddPool), uint64(1));
        bytes memory proof = _formatMessageProof(abi.encodePacked(uint8(MessagesLib.Call.AddPool), uint64(1)));

        // Setup random set of adapters
        address[] memory testAdapters = new address[](numAdapters);
        for (uint256 i = 0; i < numAdapters; i++) {
            testAdapters[i] = address(new MockAdapter(address(gateway)));
        }
        gateway.file("adapters", testAdapters);

        // Generate random sequence of confirming messages and proofs
        uint256 it = 0;
        uint256 totalSent = 0;
        uint256[] memory sentPerAdapter = new uint256[](numAdapters);
        while (totalSent < numParallelDuplicateMessages * numAdapters) {
            it++;
            uint8 randomAdapterId =
                numAdapters > 1 ? uint8(uint256(keccak256(abi.encodePacked(entropy, it)))) % numAdapters : 0;

            if (sentPerAdapter[randomAdapterId] == numParallelDuplicateMessages) {
                // Already confirmed all the messages
                continue;
            }

            // Send the message or proof
            if (randomAdapterId == 0) {
                _send(MockAdapter(testAdapters[randomAdapterId]), message);
            } else {
                _send(MockAdapter(testAdapters[randomAdapterId]), proof);
            }

            totalSent++;
            sentPerAdapter[randomAdapterId]++;
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

    function _send(MockAdapter adapter, bytes memory message) internal {
        vm.prank(address(adapter));
        gateway.handle(message);
    }
}
