// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import {MessagesLib} from "src/libraries/MessagesLib.sol";
import {CastLib} from "src/libraries/CastLib.sol";
import "forge-std/Test.sol";

contract MessagesLibTest is Test {
    using CastLib for *;

    function setUp() public {}

    function testMessageProof() public {
        uint64 poolId = 1;
        bytes memory payload = abi.encodePacked(uint8(MessagesLib.Call.AddPool), poolId);
        bytes memory expectedHex = hex"1cfe5c5905ed051500f0e9887c795a77399087aa6cbcbf48b19a9d162ba1b7fa76";

        assertEq(abi.encodePacked(uint8(MessagesLib.Call.MessageProof), keccak256(payload)), expectedHex);

        (bytes32 decodedProof) = MessagesLib.parseMessageProof(expectedHex);
        assertEq(decodedProof, keccak256(payload));
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
