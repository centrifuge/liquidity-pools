// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.7.6;
pragma abicoder v2;

import {TypedMemView} from "memview-sol/TypedMemView.sol";
import {ConnectorMessages} from "src/Messages.sol";
import "forge-std/Test.sol";

contract MessagesTest is Test {
    using TypedMemView for bytes;
    using TypedMemView for bytes29;
    using ConnectorMessages for bytes29;

    function setUp() public {}

    function testAddPoolEncoding() public {
        assertEq(
            ConnectorMessages.formatAddPool(0),
            fromHex("010000000000000000")
        );       
        assertEq(
            ConnectorMessages.formatAddPool(1),
            fromHex("010000000000000001")
        );
        assertEq(
            ConnectorMessages.formatAddPool(12378532),
            fromHex("010000000000bce1a4")
        );
    }

    function testAddPoolDecoding() public {
        uint64 actualPoolId1 = ConnectorMessages.parseAddPool(fromHex("010000000000000000").ref(0));
        assertEq(
            uint256(actualPoolId1),
            0
        );
     
        uint64 actualPoolId2 = ConnectorMessages.parseAddPool(fromHex("010000000000000001").ref(0));
        assertEq(
            uint256(actualPoolId2),
            1
        );

        uint64 actualPoolId3 = ConnectorMessages.parseAddPool(fromHex("010000000000bce1a4").ref(0));
        assertEq(
            uint256(actualPoolId3),
            12378532
        );
    }

    function testAddPoolEquivalence(uint64 poolId) public {
        bytes memory _message = ConnectorMessages.formatAddPool(poolId);
        uint64 decodedPoolId = ConnectorMessages.parseAddPool(_message.ref(0));
        assertEq(uint256(decodedPoolId), uint256(poolId));
    }

    function testAddTrancheEncoding() public {
        assertEq(
            ConnectorMessages.formatAddTranche(12378532, bytes16(hex"811acd5b3f17c06841c7e41e9e04cb1b"), "Some Name", "SYMBOL", 1000000000000000000000000000),
            hex"020000000000bce1a4811acd5b3f17c06841c7e41e9e04cb1b536f6d65204e616d65000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000053594d424f4c000000000000000000000000000000000000000000000000000000000000033b2e3c9fd0803ce8000000"
        );
    }

    function testAddTrancheDecoding() public {
        (uint64 decodedPoolId, bytes16 decodedTrancheId, string memory decodedTokenName, string memory decodedTokenSymbol, uint128 decodedPrice) = ConnectorMessages.parseAddTranche(fromHex("020000000000bce1a4811acd5b3f17c06841c7e41e9e04cb1b536f6d65204e616d65000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000053594d424f4c000000000000000000000000000000000000000000000000000000000000033b2e3c9fd0803ce8000000").ref(0));
        assertEq(uint(decodedPoolId), uint(12378532));
        assertEq(decodedTrancheId, bytes16(hex"811acd5b3f17c06841c7e41e9e04cb1b"));
        assertEq(decodedTokenName, bytes32ToString(bytes32("Some Name")));
        assertEq(decodedTokenSymbol, bytes32ToString(bytes32("SYMBOL")));
        assertEq(decodedPrice, uint(1000000000000000000000000000));
    }

    function testAddTrancheEquivalence(uint64 poolId, bytes16 trancheId, string memory tokenName, string memory tokenSymbol, uint128 price)
        public
    {
        bytes memory _message = ConnectorMessages.formatAddTranche(
            poolId,
            trancheId,
            tokenName,
            tokenSymbol,
            price
        );
        (uint64 decodedPoolId, bytes16 decodedTrancheId, string memory decodedTokenName, string memory decodedTokenSymbol, uint128 decodedPrice) = ConnectorMessages
            .parseAddTranche(_message.ref(0));
        assertEq(uint(decodedPoolId), uint(poolId));
        assertEq(decodedTrancheId, trancheId);
        // Comparing raw input to output can erroneously fail when a byte string is given.
        // Intended behaviour is that byte strings will be treated as bytes and converted to strings instead
        // of treated as strings themselves. This conversion from string to bytes32 to string is used to simulate
        // this intended behaviour.
        assertEq(decodedTokenName, bytes32ToString(stringToBytes32(tokenName)));
        assertEq(decodedTokenSymbol, bytes32ToString(stringToBytes32(tokenSymbol)));
        assertEq(uint(decodedPrice), uint(price));
    }

    // Note: UpdateMember encodes differently in Solidity compared to the Rust counterpart because `user` is a 20-byte
    // value in Solidity while it is 32-byte in Rust. However, UpdateMember messages coming from the cent-chain will
    // be handled correctly as the last 12 bytes out of said 32 will be ignored.
    function testUpdateMemberEncoding() public {
        assertEq(
            ConnectorMessages.formatUpdateMember(2, bytes16(hex"811acd5b3f17c06841c7e41e9e04cb1b"), 0x1231231231231231231231231231231231231231, 1706260138),
            hex"040000000000000002811acd5b3f17c06841c7e41e9e04cb1b12312312312312312312312312312312312312310000000000000000000000000000000065b376aa"
        );
    }

    // We use an UpdateMember encoded message generated in the cent-chain to
    // verify we handle the 32 to 20 bytes address compatibility as expected.
    function testUpdateMemberDecoding() public {
        (uint64 decodedPoolId, bytes16 decodedTrancheId, address decodedUser, uint64 decodedValidUntil) = ConnectorMessages.parseUpdateMember(fromHex("040000000000000002811acd5b3f17c06841c7e41e9e04cb1b12312312312312312312312312312312312312312312312312312312312312310000000065b376aa").ref(0));
        assertEq(uint(decodedPoolId), uint(2));
        assertEq(decodedTrancheId, hex"811acd5b3f17c06841c7e41e9e04cb1b");
        assertEq(decodedUser, 0x1231231231231231231231231231231231231231);
        assertEq(decodedValidUntil, uint(1706260138));
    }

    function testUpdateMemberEquivalence(
        uint64 poolId,
        bytes16 trancheId,
        address user,
        uint64 validUntil
    ) public {
        bytes memory _message = ConnectorMessages.formatUpdateMember(
            poolId,
            trancheId,
            user,
            validUntil
        );
        (
            uint64 decodedPoolId,
            bytes16 decodedTrancheId,
            address decodedUser,
            uint64 decodedValidUntil
        ) = ConnectorMessages.parseUpdateMember(_message.ref(0));
        assertEq(uint(decodedPoolId), uint(poolId));
        assertEq(decodedTrancheId, trancheId);
        assertEq(decodedUser, user);
        assertEq(uint(decodedValidUntil), uint(validUntil));
    }

    function testUpdateTokenPriceEncoding() public {
        assertEq(
            ConnectorMessages.formatUpdateTokenPrice(1, bytes16(hex"811acd5b3f17c06841c7e41e9e04cb1b"), 1000000000000000000000000000),
            fromHex("030000000000000001811acd5b3f17c06841c7e41e9e04cb1b00000000033b2e3c9fd0803ce8000000")
            );
    }

      function testUpdateTokenPriceDecoding() public {
        (uint64 decodedPoolId, bytes16 decodedTrancheId, uint128 decodedPrice) = ConnectorMessages.parseUpdateTokenPrice(fromHex("030000000000000001811acd5b3f17c06841c7e41e9e04cb1b00000000033b2e3c9fd0803ce8000000").ref(0));
        assertEq(uint(decodedPoolId), uint(1));
        assertEq(decodedTrancheId, bytes16(hex"811acd5b3f17c06841c7e41e9e04cb1b"));
        assertEq(decodedPrice, uint(1000000000000000000000000000));
    }

    function testUpdateTokenPriceEquivalence(
        uint64 poolId,
        bytes16 trancheId,
        uint128 price
    ) public {
        bytes memory _message = ConnectorMessages.formatUpdateTokenPrice(
            poolId,
            trancheId,
            price
        );
        (
            uint64 decodedPoolId,
            bytes16 decodedTrancheId,
            uint128 decodedPrice
        ) = ConnectorMessages.parseUpdateTokenPrice(_message.ref(0));
        assertEq(uint256(decodedPoolId), uint256(poolId));
        assertEq(decodedTrancheId, trancheId);
        assertEq(uint(decodedPrice), uint(price));
    }

    // Convert an hexadecimal character to their value
    function fromHexChar(uint8 c) internal pure returns (uint8) {
        if (bytes1(c) >= bytes1("0") && bytes1(c) <= bytes1("9")) {
            return c - uint8(bytes1("0"));
        }
        if (bytes1(c) >= bytes1("a") && bytes1(c) <= bytes1("f")) {
            return 10 + c - uint8(bytes1("a"));
        }
        if (bytes1(c) >= bytes1("A") && bytes1(c) <= bytes1("F")) {
            return 10 + c - uint8(bytes1("A"));
        }
        revert("Failed to encode hex char");
    }

    // Convert an hexadecimal string to raw bytes
    function fromHex(string memory s) internal pure returns (bytes memory) {
        bytes memory ss = bytes(s);
        require(ss.length % 2 == 0); // length must be even
        bytes memory r = new bytes(ss.length / 2);

        for (uint256 i = 0; i < ss.length / 2; ++i) {
            r[i] = bytes1(
                fromHexChar(uint8(ss[2 * i])) *
                    16 +
                    fromHexChar(uint8(ss[2 * i + 1]))
            );
        }
        return r;
    }

    function stringToBytes32(string memory source) internal pure returns (bytes32 result) {
        bytes memory tempEmptyStringTest = bytes(source);
        if (tempEmptyStringTest.length == 0) {
            return 0x0;
        }

        assembly {
            result := mload(add(source, 32))
        }
    }

    function bytes32ToString(bytes32 _bytes32) internal pure returns (string memory) {
        uint8 i = 0;
        while(i < 32 && _bytes32[i] != 0) {
            i++;
        }

        bytes memory bytesArray = new bytes(i);
        for (i = 0; i < 32 && _bytes32[i] != 0; i++) {
            bytesArray[i] = _bytes32[i];
        }
        return string(bytesArray);
    }
}