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
     * 0-1: call type
     * 1-5: poolId
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
     * 0-1: call type
     * 1-5: poolId
     * 6-22: trancheId
     *
     * TODO: consider adding a message ID
     */
    function formatAddTranche(uint64 poolId, uint8[] memory trancheId) internal pure returns (bytes memory) {
        return abi.encodePacked(uint8(Call.AddTranche), poolId, trancheId);
    }

    function isAddTranche(bytes29 _msg) internal pure returns (bool) {
        return messageType(_msg) == Call.AddTranche;
    }

    function parseAddTranche(bytes29 _msg) internal pure returns (uint64 poolId, uint8[] memory trancheId) {
        poolId = uint64(_msg.indexUint(1, 8));
        // trancheId = uint8[];
        // for (uint i = 0; i < 16; i++) {
        //     trancheId.push(uint8(_msg.indexUint(i + 5, 1)));
        // }
    }
}