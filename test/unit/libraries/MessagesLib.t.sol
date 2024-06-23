// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import {MessagesLib} from "src/libraries/MessagesLib.sol";
import {CastLib} from "src/libraries/CastLib.sol";
import {BytesLib} from "src/libraries/BytesLib.sol";
import "forge-std/Test.sol";

contract MessagesLibTest is Test {
    using CastLib for *;
    using BytesLib for bytes;

    function setUp() public {}

    function testMessageType() public {
        uint64 poolId = 1;
        bytes memory payload = abi.encodePacked(uint8(MessagesLib.Call.AddPool), poolId);

        assertTrue(MessagesLib.messageType(payload) == MessagesLib.Call.AddPool);
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
