// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

/// @title  ArrayLib
library ArrayLib {
    function countNonZeroValues(uint16[8] memory arr) internal pure returns (uint8 count) {
        for (uint256 i; i < arr.length; ++i) {
            if (arr[i] > 0) ++count;
        }
    }

    function decreaseFirstNValues(uint16[8] storage arr, uint8 numValues, uint16 decrease) internal {
        for (uint256 i; i < arr.length; ++i) {
            if (numValues == 0) return;

            if (arr[i] > 0) {
                arr[i] -= decrease;
                numValues--;
            }
        }
    }

    function isEmpty(uint16[8] memory arr) internal pure returns (bool) {
        for (uint256 i; i < arr.length; ++i) {
            if (arr[i] > 0) return false;
        }
        return true;
    }
}
