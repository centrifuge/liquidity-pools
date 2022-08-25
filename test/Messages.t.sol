// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.7.6;
pragma abicoder v2;

import {TypedMemView} from "@summa-tx/memview-sol/contracts/TypedMemView.sol";
import {ConnectorMessages} from "src/Messages.sol";
import {TestUtils} from "test/utils/TestUtils.sol";
import "forge-std/Test.sol";

contract MessagesTest is Test {
    using TypedMemView for bytes;
    using TypedMemView for bytes29;
    using ConnectorMessages for bytes29;

    function setUp() public {}

    function testAddPoolEncoding() public {
        assertEq(
            ConnectorMessages.formatAddPool(0),
            TestUtils.fromHex("010000000000000000")
        );       
        assertEq(
            ConnectorMessages.formatAddPool(1),
            TestUtils.fromHex("010000000000000001")
        );
        assertEq(
            ConnectorMessages.formatAddPool(12378532),
            TestUtils.fromHex("010000000000bce1a4")
        );
    }

    function testAddPoolDecoding() public {
        uint64 actualPoolId1 = ConnectorMessages.parseAddPool(TestUtils.fromHex("010000000000000000").ref(0));
        assertEq(
            uint256(actualPoolId1),
            0
        );
     
        uint64 actualPoolId2 = ConnectorMessages.parseAddPool(TestUtils.fromHex("010000000000000001").ref(0));
        assertEq(
            uint256(actualPoolId2),
            1
        );

        uint64 actualPoolId3 = ConnectorMessages.parseAddPool(TestUtils.fromHex("010000000000bce1a4").ref(0));
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
            ConnectorMessages.formatAddTranche(0, TestUtils.toBytes16(TestUtils.fromHex("010000000000000064")), "Some Name", "SYMBOL"),
            TestUtils.fromHex("02000000000000000000000000000000000000000000000009536f6d65204e616d65000000000000000000000000000000000000000000000053594d424f4c0000000000000000000000000000000000000000000000000000")
        );
    }

    function testAddTrancheDecoding() public returns (bytes memory) {
        (uint64 decodedPoolId, bytes16 decodedTrancheId, string memory decodedTokenName, string memory decodedTokenSymbol) = ConnectorMessages.parseAddTranche(TestUtils.fromHex("02000000000000000000000000000000000000000000000009536f6d65204e616d65000000000000000000000000000000000000000000000053594d424f4c0000000000000000000000000000000000000000000000000000").ref(0));
        assertEq(uint(decodedPoolId), uint(0));
        assertEq(decodedTrancheId, TestUtils.toBytes16(TestUtils.fromHex("010000000000000064")));
        assertEq(decodedTokenName, "Some Name"); 
        assertEq(decodedTokenSymbol, "SYMBOL");
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
        // Comparing raw input to output can erroneously fail when a byte string is given. 
        // Intended behaviour is that byte strings will be treated as bytes and converted to strings instead of treated as strings themselves.
        // This conversion from string to bytes32 to string is used to simulate this intended behaviour.
        assertEq(decodedTokenName, TestUtils.bytes32ToString(TestUtils.stringToBytes32(tokenName)));
        assertEq(decodedTokenSymbol, TestUtils.bytes32ToString(TestUtils.stringToBytes32(tokenSymbol)));
    }

    function testUpdateMemberEncoding() public returns (bytes memory) {
        assertEq(
            ConnectorMessages.formatUpdateMember(5, TestUtils.toBytes16(TestUtils.fromHex("010000000000000003")), 0x225ef95fa90f4F7938A5b34234d14768cB4263dd, 1657870537), 
            TestUtils.fromHex("04000000000000000500000000000000000000000000000009225ef95fa90f4f7938a5b34234d14768cb4263dd0000000000000000000000000000000000000000000000000000000062d118c9")
            );
    }

    function testUpdateMemberDecoding() public returns (bytes memory) {
        (uint64 decodedPoolId, bytes16 decodedTrancheId, address decodedUser, uint256 decodedValidUntil) = ConnectorMessages.parseUpdateMember(TestUtils.fromHex("04000000000000000500000000000000000000000000000009225ef95fa90f4f7938a5b34234d14768cb4263dd0000000000000000000000000000000000000000000000000000000062d118c9").ref(0));
        assertEq(uint(decodedPoolId), uint(5));
        assertEq(decodedTrancheId, TestUtils.toBytes16(TestUtils.fromHex("010000000000000003")));
        assertEq(decodedUser, 0x225ef95fa90f4F7938A5b34234d14768cB4263dd);
        assertEq(decodedValidUntil, uint(1657870537));
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

    function testUpdateTokenPriceEncoding() public returns (bytes memory) {
        assertEq(
            ConnectorMessages.formatUpdateTokenPrice(3, TestUtils.toBytes16(TestUtils.fromHex("010000000000000005")), 100), 
            TestUtils.fromHex("030000000000000003000000000000000000000000000000090000000000000000000000000000000000000000000000000000000000000064")
            );
    }

      function testUpdateTokenPriceDecoding() public returns (bytes memory) {
        (uint64 decodedPoolId, bytes16 decodedTrancheId, uint256 decodedPrice) = ConnectorMessages.parseUpdateTokenPrice(TestUtils.fromHex("030000000000000003000000000000000000000000000000090000000000000000000000000000000000000000000000000000000000000064").ref(0));
        assertEq(uint(decodedPoolId), uint(3));
        assertEq(decodedTrancheId, TestUtils.toBytes16(TestUtils.fromHex("010000000000000005")));
        assertEq(decodedPrice, uint(100));
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
}