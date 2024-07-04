// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.26;

/// @title  TransientStorage
library TransientStorage {
    function tstore(bytes32 slot, address value) internal {
        assembly {
            tstore(slot, value)
        }
    }

    function tstore(bytes32 slot, uint256 value) internal {
        assembly {
            tstore(slot, value)
        }
    }

    function tloadAddress(bytes32 slot) internal returns (address value) {
        assembly {
            value := tload(slot)
        }
    }

    function tloadUint256(bytes32 slot) internal returns (uint256 value) {
        assembly {
            value := tload(slot)
        }
    }
}
