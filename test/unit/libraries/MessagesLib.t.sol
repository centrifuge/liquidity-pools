// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import {MessagesLib} from "src/libraries/MessagesLib.sol";
import {CastLib} from "src/libraries/CastLib.sol";
import "forge-std/Test.sol";

contract MessagesLibTest is Test {
    using CastLib for *;

    function setUp() public {}

    function testMessageType() public {
        uint64 poolId = 1;
        bytes memory payload = abi.encodePacked(uint8(MessagesLib.Call.AddPool), poolId);

        assertTrue(MessagesLib.messageType(payload) == MessagesLib.Call.AddPool);
    }

    function testMessageProof() public {
        uint64 poolId = 1;
        bytes memory payload = abi.encodePacked(uint8(MessagesLib.Call.AddPool), poolId);
        bytes memory expectedHex = hex"1cfe5c5905ed051500f0e9887c795a77399087aa6cbcbf48b19a9d162ba1b7fa76";

        assertEq(abi.encodePacked(uint8(MessagesLib.Call.MessageProof), keccak256(payload)), expectedHex);

        (bytes32 decodedProof) = MessagesLib.parseMessageProof(expectedHex);
        assertEq(decodedProof, keccak256(payload));
    }

    function testInitiateMessageRecovery() public {
        uint64 poolId = 1;
        bytes32 messageHash = keccak256(abi.encodePacked(uint8(MessagesLib.Call.AddPool), poolId));
        address router = makeAddr("Router");

        bytes memory payload =
            abi.encodePacked(uint8(MessagesLib.Call.InitiateMessageRecovery), messageHash, address(router).toBytes32());

        (bytes32 decodedMessageHash, address decodedRouter) = MessagesLib.parseInitiateMessageRecovery(payload);
        assertEq(decodedMessageHash, messageHash);
        assertEq(decodedRouter, router);

        assertTrue(MessagesLib.isRecoveryMessage(payload));
    }

    function testDisputeMessageRecovery() public {
        uint64 poolId = 1;
        bytes32 messageHash = keccak256(abi.encodePacked(uint8(MessagesLib.Call.AddPool), poolId));

        bytes memory payload = abi.encodePacked(uint8(MessagesLib.Call.DisputeMessageRecovery), messageHash);

        (bytes32 decodedMessageHash) = MessagesLib.parseDisputeMessageRecovery(payload);
        assertEq(decodedMessageHash, messageHash);

        assertTrue(MessagesLib.isRecoveryMessage(payload));
    }

    function testFormatDomainCentrifuge() public {
        assertEq(MessagesLib.formatDomain(MessagesLib.Domain.Centrifuge), hex"000000000000000000");
    }

    function testFormatDomainMoonbeam() public {
        assertEq(MessagesLib.formatDomain(MessagesLib.Domain.EVM, 1284), hex"010000000000000504");
    }

    function testFormatDomainMoonbaseAlpha() public {
        assertEq(MessagesLib.formatDomain(MessagesLib.Domain.EVM, 1287), hex"010000000000000507");
    }

    function testFormatDomainAvalanche() public {
        assertEq(MessagesLib.formatDomain(MessagesLib.Domain.EVM, 43114), hex"01000000000000a86a");
    }
}
