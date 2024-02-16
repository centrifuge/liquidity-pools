// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

library BitmapLib {
    function setBit(uint256 bitmap, uint256 index, bool isTrue) internal pure returns (uint256) {
        return bitmap | (uint256(isTrue ? 1 : 0) << index);
    }

    function getBit(uint256 bitmap, uint256 index) internal pure returns (bool) {
        uint256 bitAtIndex = bitmap & (1 << index);
        return bitAtIndex > 0;
    }
}
