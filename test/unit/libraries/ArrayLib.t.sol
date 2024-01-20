// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import "forge-std/Test.sol";
import {ArrayLib} from "src/libraries/ArrayLib.sol";

contract ArrayLibTest is Test {
    uint16[8] testArray;

    function testCountNonZeroValues(uint8 numNonZeroes) public {
        numNonZeroes = uint8(bound(numNonZeroes, 0, 8));
        uint16[8] memory arr = _randomArray(numNonZeroes);

        assertEq(ArrayLib.countNonZeroValues(arr), numNonZeroes);
    }

    // function testDecreaseFirstNValues(uint8 numNonZeroes, uint8 numValuesToDecrease) public {
    //     numNonZeroes = uint8(bound(numNonZeroes, 0, 8));
    //     numValuesToDecrease = uint8(bound(numValuesToDecrease, 0, 8));
    //     testArray = _randomArray(8);

    //     // Decreasing by 1 should reduce by numNonZeroes since zero values cannot be decreased
    //     ArrayLib.decreaseFirstNValues(testArray, numValuesToDecrease, 1);
    //     assertEq(_count(arr) - _count(decreasedArr), numNonZeroes);
    // }

    function testIsEmpty(uint8 numNonZeroes) public {
        numNonZeroes = uint8(bound(numNonZeroes, 0, 8));
        uint16[8] memory arr = _randomArray(numNonZeroes);

        // Array is only empty if there are no zeros
        assertEq(ArrayLib.isEmpty(arr), numNonZeroes == 0);
    }

    function _randomArray(uint8 numNonZeroes) internal view returns (uint16[8] memory arr) {
        for (uint256 i; i < numNonZeroes; i++) {
            arr[i] = _randomUint16(1, type(uint16).max);
        }
    }

    function _count(uint16[8] memory arr) internal view returns (uint8 count) {
        for (uint256 i; i < arr.length; i++) {
            count += uint8(arr[i]);
        }
    }

    function _randomUint16(uint16 minValue, uint16 maxValue) internal view returns (uint16) {
        uint256 nonce = 1;

        if (maxValue == 1) {
            return 1;
        }

        uint16 value =
            uint16(uint256(keccak256(abi.encodePacked(block.timestamp, address(this), nonce))) % (maxValue - minValue));
        return value + minValue;
    }
}
