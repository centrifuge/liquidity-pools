// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import "forge-std/Test.sol";
import {IERC20} from "src/interfaces/IERC20.sol";
import {BitmapLib} from "src/libraries/BitmapLib.sol";

contract BitmapLibTest is Test {
    using BitmapLib for uint256;

    mapping(uint8 bit => bool) booleanMapping;

    function testSetGetBitEquivalence(bool[] memory input) public {
        vm.assume(input.length <= 255);

        // Set all values from input
        uint256 output;
        for (uint8 i = 0; i < input.length; i++) {
            output = output.setBit(i, input[i]);
        }

        // Check that input == output
        for (uint8 j = 0; j < input.length; j++) {
            assertEq(output.getBit(j), input[j]);
        }
    }

    function testSettingRandomBit(uint8 randomBit) public {
        uint256 bitmap = uint256(0).setBit(randomBit, true);
        booleanMapping[randomBit] = true;

        for (uint256 i = 0; i < 255; i++) {
            assertEq(bitmap.getBit(randomBit), booleanMapping[randomBit]);
        }
    }

    function testGetFirstN(uint8 n) public {
        n = uint8(bound(n, 1, 255));

        uint256 allOnes = type(uint256).max;
        uint256 firstN = allOnes.getFirstN(n);

        uint256 equiv = uint256(0);
        for (uint8 i = 0; i < n; i++) {
            equiv = equiv.setBit(i, true);
        }

        assertEq(firstN, equiv);
    }
}
