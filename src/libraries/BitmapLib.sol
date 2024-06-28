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

    function shiftLeft(uint64 value, uint256 shift) internal pure returns (uint128) {
        return uint128(uint64(value)) << shift;
    }

    /// @notice Concatenate uint64 values to create a uint128 value
    function concat(uint64 left, uint64 right) internal pure returns (uint128) {
        return uint128(uint64(left)) << 64 | uint64(right);
    }

    /// @notice Concatenate uint128 values to create a uint256 value
    function concat(uint128 left, uint128 right) internal pure returns (uint256) {
        return uint256(uint128(left)) << 128 | uint128(right);
    }
}
