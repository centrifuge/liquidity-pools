// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.7.6;
pragma abicoder v2;

import {TypedMemView} from "@summa-tx/memview-sol/contracts/TypedMemView.sol";
import { ConnectorMessages } from "src/Messages.sol";
import "forge-std/Test.sol";

contract MessagesTest is Test {
    using TypedMemView for bytes;
    using TypedMemView for bytes29;
    using ConnectorMessages for bytes29;

    function setUp() public {}

    function testAddPoolEquivalence(uint64 poolId) public {
        bytes memory _message = ConnectorMessages.formatAddPool(poolId);
        uint64 decodedPoolId = ConnectorMessages.parseAddPool(_message.ref(0));
        assertEq(uint256(decodedPoolId), uint256(poolId));
    }

    function testAddTrancheEquivalence(uint64 poolId, bytes16 trancheId) public {
        bytes memory _message = ConnectorMessages.formatAddTranche(poolId, trancheId);
        (uint64 decodedPoolId, bytes16 decodedTrancheId) = ConnectorMessages.parseAddTranche(_message.ref(0));
        assertEq(uint256(decodedPoolId), uint256(poolId));
        assertEq(decodedTrancheId, trancheId);
    }

    function testUpdateMemberEquivalence(uint64 poolId, bytes16 trancheId, address user, uint256 amount) public {
        bytes memory _message = ConnectorMessages.formatUpdateMember(poolId, trancheId, user, amount);
        (uint64 decodedPoolId, bytes16 decodedTrancheId, address decodedUser, uint256 decodedAmount) = ConnectorMessages.parseUpdateMember(_message.ref(0));
        assertEq(uint256(decodedPoolId), uint256(poolId));
        assertEq(decodedTrancheId, trancheId);
        assertEq(decodedUser, user);
        assertEq(decodedAmount, amount);
    }

    function testUpdateTokenPriceEquivalence(uint64 poolId, bytes16 trancheId, uint256 price) public {
        bytes memory _message = ConnectorMessages.formatUpdateTokenPrice(poolId, trancheId, price);
        (uint64 decodedPoolId, bytes16 decodedTrancheId, uint256 decodedPrice) = ConnectorMessages.parseUpdateTokenPrice(_message.ref(0));
        assertEq(uint256(decodedPoolId), uint256(poolId));
        assertEq(decodedTrancheId, trancheId);
        assertEq(decodedPrice, price);
    }

}