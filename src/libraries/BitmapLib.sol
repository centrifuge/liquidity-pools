// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

/// @title  BitmapLib
library BitmapLib {
    function setBit(uint128 bitmap, uint128 index, bool isTrue) internal pure returns (uint128) {
        if (isTrue) {
            return bitmap | (uint128(1) << index);
        } else {
            return bitmap & ~(uint128(1) << index);
        }
    }

    function getBit(uint128 bitmap, uint128 index) internal pure returns (bool) {
        uint128 bitAtIndex = uint128(bitmap & (1 << index));
        return bitAtIndex > 0;
    }

    /// @notice Get n least significant bits from the bitmap
    function getLSBits(uint256 bitmap, uint256 n) internal pure returns (uint256) {
        return bitmap & (2 ** n - 1);
    }

    /// @notice Get n most significant bits from the bitmap
    function getMSBits(uint256 bitmap, uint256 n) internal pure returns (uint256) {
        return bitmap >> n;
    }

    /// @notice Concatenate uint128 values to create a uint256 value
    function concat(uint128 left, uint128 right) internal pure returns (uint256) {
        return uint256(uint128(left)) << 128 | uint128(right);
    }
}
