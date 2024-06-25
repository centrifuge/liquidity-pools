// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import "test/BaseTest.sol";
import {MockGateway} from "test/mocks/MockGateway.sol";
import {MockRouter} from "test/mocks/MockRouter.sol";
import {MockRoot} from "test/mocks/MockRoot.sol";
import {MockManager} from "test/mocks/MockManager.sol";
import {MockAxelarGasService} from "test/mocks/MockAxelarGasService.sol";
import {CastLib} from "src/libraries/CastLib.sol";

contract GatewayTest is Test {
    using CastLib for *;

    address self;

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

        router1.setReturn("estimate", uint256(1.5 gwei));
        router2.setReturn("estimate", uint256(1.25 gwei));
        router3.setReturn("estimate", uint256(0.75 gwei));

        gasService.setReturn("estimate", uint256(0.5 gwei));

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

        self = address(this);
    }

    // --- Administration ---
    function testFile() public {
        // fail: unrecognized param
        vm.expectRevert(bytes("Gateway/file-unrecognized-param"));
        gateway.file("random", self);

        vm.expectRevert(bytes("Gateway/file-unrecognized-param"));
        gateway.file("random", uint8(1), self);

        assertEq(address(gateway.poolManager()), address(poolManager));
        assertEq(address(gateway.investmentManager()), address(investmentManager));
        assertEq(address(gateway.gasService()), address(gasService));

        // success
        gateway.file("poolManager", self);
        assertEq(address(gateway.poolManager()), self);
        gateway.file("investmentManager", self);
        assertEq(address(gateway.investmentManager()), self);
        gateway.file("gasService", self);
        assertEq(address(gateway.gasService()), self);

        // remove self from wards
        gateway.deny(self);
        // auth fail
        vm.expectRevert(bytes("Auth/not-authorized"));
        gateway.file("poolManager", self);
    }

    // --- Permissions ---
    function testOnlyRoutersCanCall() public {
        gateway.file("routers", threeMockRouters);

        bytes memory message = hex"020000000000bce1a4";

        vm.expectRevert(bytes("Gateway/invalid-router"));
        vm.prank(makeAddr("randomUser"));
        gateway.handle(message);

        //success
        vm.prank(address(router1));
        gateway.handle(message);
    }

    function testOnlyManagersCanCall(uint64 poolId) public {
        gateway.file("routers", threeMockRouters);

        vm.expectRevert(bytes("Gateway/invalid-manager"));
        gateway.send(abi.encodePacked(uint8(MessagesLib.Call.AddPool), poolId), self);

        gateway.file("poolManager", self);
        gateway.send(abi.encodePacked(uint8(MessagesLib.Call.AddPool), poolId), self);

        gateway.file("poolManager", address(poolManager));
        vm.expectRevert(bytes("Gateway/invalid-manager"));
        gateway.send(abi.encodePacked(uint8(MessagesLib.Call.AddPool), poolId), self);

        gateway.file("investmentManager", self);
        gateway.send(abi.encodePacked(uint8(MessagesLib.Call.AddPool), poolId), self);
    }

    // --- Dynamic managers ---
    function testCustomManager() public {
        uint8 messageId = 40;
        address[] memory routers = new address[](1);
        routers[0] = address(router1);

        gateway.file("routers", routers);

        MockManager mgr = new MockManager();

        bytes memory message = abi.encodePacked(messageId);
        vm.expectRevert(bytes("Gateway/unregistered-message-id"));
        vm.prank(address(router1));
        gateway.handle(message);

        assertEq(mgr.received(message), 0);

        gateway.file("message", messageId, address(mgr));
        vm.prank(address(router1));
        gateway.handle(message);

        assertEq(mgr.received(message), 1);
        assertEq(mgr.values_bytes("handle_message"), message);
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

    function testPrepayment() public {
        uint256 topUpAmount = 1 gwei;

        vm.expectRevert(bytes("Gateway/only-endorsed-can-topup"));
        gateway.topUp{value: topUpAmount}();

        root.setReturn("endorsed_user", true);
        vm.expectRevert(bytes("Gateway/cannot-topup-with-nothing"));
        gateway.topUp{value: 0}();

        uint256 balanceBeforeTopUp = address(gateway).balance;
        gateway.topUp{value: topUpAmount}();
        uint256 balanceAfterTopUp = address(gateway).balance;
        assertEq(balanceAfterTopUp, balanceBeforeTopUp + topUpAmount);
    }

    function testOutgoingMessagingWithNotEnoughPrepayment() public {
        gateway.file("routers", threeMockRouters);

        bytes memory message = abi.encodePacked(uint8(MessagesLib.Call.AddPool), uint64(1));
        bytes memory proof = _formatMessageProof(message);

        root.setReturn("endorsed_user", true);

        uint256 balanceBeforeTx = address(gateway).balance;
        uint256 topUpAmount = 10 wei;

        gateway.topUp{value: topUpAmount}();
        vm.expectRevert(bytes("Gateway/not-enough-gas-funds"));
        vm.prank(address(investmentManager));
        gateway.send(message, self);

        assertEq(gasService.calls("shouldRefuel"), 0);

        assertEq(router1.calls("pay"), 0);
        assertEq(router2.calls("pay"), 0);
        assertEq(router3.calls("pay"), 0);

        assertEq(router1.sent(message), 0);
        assertEq(router2.sent(proof), 0);
        assertEq(router3.sent(proof), 0);

        assertEq(address(gateway).balance, balanceBeforeTx + topUpAmount);
    }

    function testOutgoingMessagingWithPrepayment() public {
        gateway.file("routers", threeMockRouters);

        bytes memory message = abi.encodePacked(uint8(MessagesLib.Call.AddPool), uint64(1));
        bytes memory proof = _formatMessageProof(message);

        root.setReturn("endorsed_user", true);

        uint256 balanceBeforeTx = address(gateway).balance;

        (uint256[] memory tranches, uint256 total) = gateway.estimate(message);
        gateway.topUp{value: total}();

        vm.prank(address(investmentManager));
        gateway.send(message, self);

        assertEq(gasService.calls("shouldRefuel"), 0);

        for (uint256 i; i < threeMockRouters.length; i++) {
            MockRouter currentRouter = MockRouter(threeMockRouters[i]);
            uint256[] memory metadata = currentRouter.callsWithValue("pay");
            assertEq(metadata.length, 1);
            assertEq(metadata[0], tranches[i]);

            assertEq(currentRouter.sent(i == 0 ? message : proof), 1);
        }
        assertEq(address(gateway).balance, balanceBeforeTx);

        uint256 fuel = uint256(vm.load(address(gateway), bytes32(0x0)));
        assertEq(fuel, 0);
    }

    function testOutgoingMessagingWithExtraPrepayment() public {
        gateway.file("routers", threeMockRouters);

        bytes memory message = abi.encodePacked(uint8(MessagesLib.Call.AddPool), uint64(1));
        bytes memory proof = _formatMessageProof(message);

        root.setReturn("endorsed_user", true);

        uint256 balanceBeforeTx = address(gateway).balance;

        (uint256[] memory tranches, uint256 total) = gateway.estimate(message);
        uint256 extra = 10 wei;
        uint256 topUpAmount = total + extra;
        gateway.topUp{value: topUpAmount}();

        vm.prank(address(investmentManager));
        gateway.send(message, self);

        assertEq(gasService.calls("shouldRefuel"), 0);

        for (uint256 i; i < threeMockRouters.length; i++) {
            MockRouter currentRouter = MockRouter(threeMockRouters[i]);
            uint256[] memory metadata = currentRouter.callsWithValue("pay");
            assertEq(metadata.length, 1);
            assertEq(metadata[0], tranches[i]);

            assertEq(currentRouter.sent(i == 0 ? message : proof), 1);
        }
        assertEq(address(gateway).balance, balanceBeforeTx + extra);
        uint256 fuel = uint256(vm.load(address(gateway), bytes32(0x0)));
        assertEq(fuel, 0);
    }

    function testingOutgoingMessagingWithCoveredPayment() public {
        gateway.file("routers", threeMockRouters);

        bytes memory message = abi.encodePacked(uint8(MessagesLib.Call.AddPool), uint64(1));
        bytes memory proof = _formatMessageProof(message);

        uint256 balanceBeforeTx = address(gateway).balance;

        (uint256[] memory tranches, uint256 total) = gateway.estimate(message);

        assertEq(_quota(), 0);

        vm.prank(address(investmentManager));
        gateway.send(message, self);

        assertEq(gasService.calls("shouldRefuel"), 1);

        for (uint256 i; i < threeMockRouters.length; i++) {
            MockRouter currentRouter = MockRouter(threeMockRouters[i]);
            uint256[] memory metadata = currentRouter.callsWithValue("pay");
            assertEq(metadata.length, 1);
            assertEq(metadata[0], tranches[i]);

            assertEq(currentRouter.sent(i == 0 ? message : proof), 1);
        }
        assertEq(address(gateway).balance, balanceBeforeTx - total);
        assertEq(_quota(), 0);
    }

    function testingOutgoingMessagingWithPartiallyCoveredPayment() public {
        gateway.file("routers", threeMockRouters);

        bytes memory message = abi.encodePacked(uint8(MessagesLib.Call.AddPool), uint64(1));
        bytes memory proof = _formatMessageProof(message);

        (uint256[] memory tranches,) = gateway.estimate(message);

        uint256 fundsToCoverTwoRoutersOnly = tranches[0] + tranches[1];
        vm.deal(address(gateway), fundsToCoverTwoRoutersOnly);
        uint256 balanceBeforeTx = address(gateway).balance;

        assertEq(balanceBeforeTx, fundsToCoverTwoRoutersOnly);
        assertEq(_quota(), 0);

        vm.prank(address(investmentManager));
        gateway.send(message, self);

        assertEq(gasService.calls("shouldRefuel"), 1);

        uint256[] memory r1Metadata = router1.callsWithValue("pay");
        assertEq(r1Metadata.length, 1);
        assertEq(r1Metadata[0], tranches[0]);
        assertEq(router1.sent(message), 1);

        uint256[] memory r2Metadata = router2.callsWithValue("pay");
        assertEq(r2Metadata.length, 1);
        assertEq(r2Metadata[0], tranches[1]);
        assertEq(router2.sent(proof), 1);

        uint256[] memory r3Metadata = router3.callsWithValue("pay");
        assertEq(r3Metadata.length, 0);
        assertEq(router3.sent(proof), 1);

        assertEq(address(gateway).balance, balanceBeforeTx - fundsToCoverTwoRoutersOnly);
        assertEq(_quota(), 0);
    }

    function testingOutgoingMessagingWithoutBeingCovered() public {
        gateway.file("routers", threeMockRouters);

        bytes memory message = abi.encodePacked(uint8(MessagesLib.Call.AddPool), uint64(1));
        bytes memory proof = _formatMessageProof(message);

        vm.deal(address(gateway), 0);

        assertEq(_quota(), 0);

        vm.prank(address(investmentManager));
        gateway.send(message, self);

        assertEq(gasService.calls("shouldRefuel"), 1);

        uint256[] memory r1Metadata = router1.callsWithValue("pay");
        assertEq(r1Metadata.length, 0);
        assertEq(router1.sent(message), 1);

        uint256[] memory r2Metadata = router2.callsWithValue("pay");
        assertEq(r2Metadata.length, 0);
        assertEq(router2.sent(proof), 1);

        uint256[] memory r3Metadata = router3.callsWithValue("pay");
        assertEq(r3Metadata.length, 0);
        assertEq(router3.sent(proof), 1);

        assertEq(_quota(), 0);
    }

    function testingOutgoingMessagingWherePaymentCoverIsNotAllowed() public {
        gateway.file("routers", threeMockRouters);

        bytes memory message = abi.encodePacked(uint8(MessagesLib.Call.AddPool), uint64(1));

        uint256 balanceBeforeTx = address(gateway).balance;
        assertEq(balanceBeforeTx, 1 ether);
        assertEq(_quota(), 0);

        gasService.setReturn("shouldRefuel", false);

        vm.expectRevert(bytes("Gateway/not-enough-gas-funds"));
        vm.prank(address(investmentManager));
        gateway.send(message, self);

        assertEq(balanceBeforeTx, 1 ether);
        assertEq(_quota(), 0);
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

    /// @dev Use to simulate incoming message to the gateway sent by a router.
    function _send(MockRouter router, bytes memory message) internal {
        vm.prank(address(router));
        gateway.handle(message);
    }

    function _quota() internal view returns (uint256 quota) {
        quota = uint256(vm.load(address(gateway), bytes32(0x0)));
    }
}
