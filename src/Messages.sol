// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.7.6;

import "@summa-tx/memview-sol/contracts/TypedMemView.sol";

library ConnectorMessages {
    using TypedMemView for bytes;
    using TypedMemView for bytes29;

    enum Types {
        Invalid,
        AddPool
    }

    function formatAddPool(uint256 poolId) internal pure returns (bytes memory) {
        return abi.encodePacked(uint8(Types.AddPool), poolId);
    }

    function messageType(bytes29 _view) internal pure returns (Types _type) {
        _type = Types(uint8(_view.typeOf()));
    }

    function isAddPool(bytes29 _view) internal pure returns (bool) {
        return messageType(_view) == Types.AddPool;
    }
}