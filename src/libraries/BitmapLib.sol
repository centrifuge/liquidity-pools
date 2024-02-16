// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

library BitmapLib {
  function setBitInBitmap(uint256 bitmap, uint256 index) internal pure returns (uint256) {
    return bitmap | (1 << index);
  }

  function getBitFromBitmap(uint256 bitmap, uint256 index) internal pure returns (bool) {
    uint256 bitAtIndex = bitmap & (1 << index) > 0;
    return bitAtIndex > 0;
  }
}