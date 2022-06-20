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

    function formatAddPool(uint64 poolId) internal pure returns (bytes memory) {
        return abi.encodePacked(uint8(Call.AddPool), poolId);
    }

    function messageType(bytes29 _msg) internal pure returns (Call _call) {
        _call = Call(uint8(_msg.indexUint(0, 1)));
    }

    function isAddPool(bytes29 _msg) internal pure returns (bool) {
        return messageType(_msg) == Call.AddPool;
    }

    function parseAddPool(bytes29 _msg) internal pure returns (uint64 poolId) {
        return uint64(_msg.indexUint(1, 8));
    }
}