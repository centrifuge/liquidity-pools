// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.7.6;
pragma abicoder v2;

import {TypedMemView} from "@summa-tx/memview-sol/contracts/TypedMemView.sol";
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
            uint256(actualPoolId1),
            1
        );

        uint64 actualPoolId3 = ConnectorMessages.parseAddPool(fromHex("010000000000bce1a4").ref(0));
        assertEq(
            uint256(actualPoolId1),
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
            ConnectorMessages.formatAddTranche(0, toBytes16(fromHex("100")), "Some Name", "SYMBOL"),
            fromHex("010000000000000000")
        );
    }

    function testAddTrancheEquivalence(uint64 poolId, bytes16 trancheId, string memory tokenName, string memory tokenSymbol)
        public
    {
        bytes memory _message = ConnectorMessages.formatAddTranche(
            poolId,
            trancheId,
            tokenName,
            tokenSymbol
        );
        (uint64 decodedPoolId, bytes16 decodedTrancheId, string memory decodedTokenName, string memory decodedTokenSymbol) = ConnectorMessages
            .parseAddTranche(_message.ref(0));
        assertEq(uint256(decodedPoolId), uint256(poolId));
        assertEq(decodedTrancheId, trancheId);
        assertEq(decodedTokenName, tokenName);
        assertEq(decodedTokenSymbol, tokenSymbol);
    }

    function testUpdateMemberEquivalence(
        uint64 poolId,
        bytes16 trancheId,
        address user,
        uint256 amount
    ) public {
        bytes memory _message = ConnectorMessages.formatUpdateMember(
            poolId,
            trancheId,
            user,
            amount
        );
        (
            uint64 decodedPoolId,
            bytes16 decodedTrancheId,
            address decodedUser,
            uint256 decodedAmount
        ) = ConnectorMessages.parseUpdateMember(_message.ref(0));
        assertEq(uint256(decodedPoolId), uint256(poolId));
        assertEq(decodedTrancheId, trancheId);
        assertEq(decodedUser, user);
        assertEq(decodedAmount, amount);
    }

    function testUpdateTokenPriceEquivalence(
        uint64 poolId,
        bytes16 trancheId,
        uint256 price
    ) public {
        bytes memory _message = ConnectorMessages.formatUpdateTokenPrice(
            poolId,
            trancheId,
            price
        );
        (
            uint64 decodedPoolId,
            bytes16 decodedTrancheId,
            uint256 decodedPrice
        ) = ConnectorMessages.parseUpdateTokenPrice(_message.ref(0));
        assertEq(uint256(decodedPoolId), uint256(poolId));
        assertEq(decodedTrancheId, trancheId);
        assertEq(decodedPrice, price);
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

    function toBytes16(bytes memory f) internal pure returns (bytes16 fc) {
        assembly {
          fc := mload(add(f, 32))
        }
        return fc;
    }

    function testFormatAddTranche1() public returns (bytes memory) {
        uint64 poolId = 12;
        bytes16 trancheId = toBytes16(bytes("1"));
        string memory tokenName = "New Silver DROP";
        string memory tokenSymbol = "NS2DRP";
        bytes memory output = ConnectorMessages.formatAddTranche(poolId, trancheId, tokenName, tokenSymbol);
        bytes memory expected = hex"02000000000000000c310000000000000000000000000000004e65772053696c7665722044524f5000000000000000000000000000000000004e53324452500000000000000000000000000000000000000000000000000000";
        assertEq(output, expected);
    }

    function testFormatAddTranche2() public returns (bytes memory) {
        uint64 poolId = 0;
        bytes16 trancheId = toBytes16(bytes("0"));
        string memory tokenName = "Harbor Trade TIN";
        string memory tokenSymbol = "HTCTIN";
        bytes memory output = ConnectorMessages.formatAddTranche(poolId, trancheId, tokenName, tokenSymbol);
        bytes memory expected = hex"02000000000000000030000000000000000000000000000000486172626f722054726164652054494e0000000000000000000000000000000048544354494e0000000000000000000000000000000000000000000000000000";
        assertEq(output, expected);
    }

}
