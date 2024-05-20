// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

/// @title  BitmapLib
library BitmapLib {
    function setBit(uint256 bitmap, uint256 index, bool isTrue) internal pure returns (uint256) {
        if (isTrue) {
            return bitmap | (uint256(1) << index);
        } else {
            return bitmap & ~(uint256(1) << index);
        }
    }

    function getBit(uint256 bitmap, uint256 index) internal pure returns (bool) {
        uint256 bitAtIndex = bitmap & (1 << index);
        return bitAtIndex > 0;
    }

    /// @notice Get n least significant bits from the bitmap
    function getLSBits(uint256 bitmap, uint256 n) internal pure returns (uint256) {
        return bitmap & (2 ** n - 1);
    }
}
