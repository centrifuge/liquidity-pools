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

    uint constant TRANCHE_ID_LENGTH = 16; // [u8, 16]

    function messageType(bytes29 _msg) internal pure returns (Call _call) {
        _call = Call(uint8(_msg.indexUint(0, 1)));
    }

    /**
     * Add pool
     * 
     * 1: call type (uint8 = 1 byte)
     * 2-9: poolId (uint64 = 8 bytes)
     *
     * TODO: consider adding a message ID
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
     * 1: call type (uint8 = 1 byte)
     * 2-9: poolId (uint64 = 8 bytes)
     * 10-26: trancheId (16 bytes)
     *
     * TODO: consider adding a message ID
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
}