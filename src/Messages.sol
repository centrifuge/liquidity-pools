// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.7.6;

import "@summa-tx/memview-sol/contracts/TypedMemView.sol";

library ConnectorMessages {
    using TypedMemView for bytes;
    using TypedMemView for bytes29;

    enum Call {
        Invalid,
        AddPool,
        AddTranche,
        UpdateTokenPrice,
        UpdateMember,
        TransferTo
    }

    function messageType(bytes29 _msg) internal pure returns (Call _call) {
        _call = Call(uint8(_msg.indexUint(0, 1)));
    }

    /**
     * Add pool
     * 
     * 0: call type (uint8 = 1 byte)
     * 1-8: poolId (uint64 = 8 bytes)
     */
    function formatAddPool(uint64 poolId) internal pure returns (bytes memory) {
        return abi.encodePacked(uint8(Call.AddPool), poolId);
    }

    function isAddPool(bytes29 _msg) internal pure returns (bool) {
        return messageType(_msg) == Call.AddPool;
    }

    function parseAddPool(bytes29 _msg) internal pure returns (uint64 poolId) {
        return uint64(_msg.indexUint(1, 8));
    }

    /**
     * Add tranche
     * 
     * 0: call type (uint8 = 1 byte)
     * 1-8: poolId (uint64 = 8 bytes)
     * 9-25: trancheId (16 bytes)
     */
    function formatAddTranche(uint64 poolId, bytes16 trancheId) internal pure returns (bytes memory) {
        return abi.encodePacked(uint8(Call.AddTranche), poolId, trancheId);
    }

    function isAddTranche(bytes29 _msg) internal pure returns (bool) {
        return messageType(_msg) == Call.AddTranche;
    }

    function parseAddTranche(bytes29 _msg) internal pure returns (uint64 poolId, bytes16 trancheId) {
        poolId = uint64(_msg.indexUint(1, 8));
        trancheId = bytes16(_msg.index(9, 16));
    }

    /**
     * Update member
     * 
     * 0: call type (uint8 = 1 byte)
     * 1-8: poolId (uint64 = 8 bytes)
     * 9-25: trancheId (16 bytes)
     * 26-46: user (Ethereum address, 20 bytes)
     * 47-78: amount (uint256 = 32 bytes)
     */
    function formatUpdateMember(uint64 poolId, bytes16 trancheId, address user, uint256 amount) internal pure returns (bytes memory) {
        return abi.encodePacked(uint8(Call.UpdateMember), poolId, trancheId, user, amount);
    }

    function isUpdateMember(bytes29 _msg) internal pure returns (bool) {
        return messageType(_msg) == Call.UpdateMember;
    }

    function parseUpdateMember(bytes29 _msg) internal pure returns (uint64 poolId, bytes16 trancheId, address user, uint256 amount) {
        poolId = uint64(_msg.indexUint(1, 8));
        trancheId = bytes16(_msg.index(9, 16));
        user = address(bytes20(_msg.index(25, 20)));
        amount = uint256(_msg.index(45, 32));
    }

    /**
     * Update token price
     * 
     * 0: call type (uint8 = 1 byte)
     * 1-8: poolId (uint64 = 8 bytes)
     * 9-25: trancheId (16 bytes)
     * 26-58: amount (uint256 = 32 bytes)
     */
    function formatUpdateTokenPrice(uint64 poolId, bytes16 trancheId, uint256 price) internal pure returns (bytes memory) {
        return abi.encodePacked(uint8(Call.UpdateTokenPrice), poolId, trancheId, price);
    }

    function isUpdateTokenPrice(bytes29 _msg) internal pure returns (bool) {
        return messageType(_msg) == Call.UpdateTokenPrice;
    }

    function parseUpdateTokenPrice(bytes29 _msg) internal pure returns (uint64 poolId, bytes16 trancheId, uint256 price) {
        poolId = uint64(_msg.indexUint(1, 8));
        trancheId = bytes16(_msg.index(9, 16));
        price = uint256(_msg.index(25, 32));
    }

}