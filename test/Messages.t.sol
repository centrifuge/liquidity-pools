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

    // function testAddTrancheEncoding(uint64 poolId, bytes16 trancheId, string memory tokenName, string memory tokenSymbol)
    //     public
    // {
    //     assert ConnectorMessages.formatAddTranche(
    //         poolId,
    //         trancheId,
    //         tokenName,
    //         tokenSymbol
    //     );
    // }

    function testAddPoolEquivalence(uint64 poolId) public {
        bytes memory _message = ConnectorMessages.formatAddPool(poolId);
        uint64 decodedPoolId = ConnectorMessages.parseAddPool(_message.ref(0));
        assertEq(uint256(decodedPoolId), uint256(poolId));
    }


    function testAddTrancheEquivalence(uint64 poolId, bytes16 trancheId, string memory tokenName, string memory tokenSymbol)
        public
    {
        // tokenSymbol = "\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0"
        // tokenSymbol = bytes(tokenSymbol);
        bytes memory _message = ConnectorMessages.formatAddTranche(
            poolId,
            trancheId,
            tokenName,
            tokenSymbol
        );
        (uint64 decodedPoolId, bytes16 decodedTrancheId, string memory decodedTokenName, string memory decodedTokenSymbol) = ConnectorMessages
            .parseAddTranche(_message.ref(0));

        tokenSymbol = string(abi.encodePacked(tokenSymbol));
        tokenName = string(abi.encodePacked(tokenName));
        console.log("!!!!!!!");
        console.log(tokenSymbol);
        console.log(tokenName);
        console.log("!!!!!!!");
        // tokenSymbol = ConnectorMessages.bytes32ToString(bytes32());
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

    function testAddTrancheEncoding() public returns (bytes memory) {
        assertEq(ConnectorMessages.formatAddTranche(12, toBytes16(bytes("1")), "New Silver DROP", "NS2DRP"), hex"02000000000000000c310000000000000000000000000000004e65772053696c7665722044524f5000000000000000000000000000000000004e53324452500000000000000000000000000000000000000000000000000000");
    }

    function testAddTrancheDecoding() public returns (bytes memory) {
        (uint64 decodedPoolId, bytes16 decodedTrancheId, string memory decodedTokenName, string memory decodedTokenSymbol) = ConnectorMessages.parseAddTranche(fromHex("02000000000000000c310000000000000000000000000000004e65772053696c7665722044524f5000000000000000000000000000000000004e53324452500000000000000000000000000000000000000000000000000000").ref(0));
        assertEq(uint(decodedPoolId), uint(12));
        assertEq(decodedTrancheId, toBytes16(bytes("1")));
        assertEq(decodedTokenName, "New Silver DROP");
        assertEq(decodedTokenSymbol, "NS2DRP");
    }

    function testUpdateMemberEncoding() public returns (bytes memory) {
        assertEq(ConnectorMessages.formatUpdateMember(5, toBytes16(bytes("2")), 0x225ef95fa90f4F7938A5b34234d14768cB4263dd, 1657870537), hex"04000000000000000532000000000000000000000000000000225ef95fa90f4f7938a5b34234d14768cb4263dd0000000000000000000000000000000000000000000000000000000062d118c9");
    }

    function testUpdateTokenPriceEncoding() public returns (bytes memory) {
        assertEq(ConnectorMessages.formatUpdateTokenPrice(3, toBytes16(bytes("1")), 1234534532534345234234345), hex"0300000000000000033100000000000000000000000000000000000000000000000000000000000000000000000001056c4048afb4a839bbe9");
    }

}
