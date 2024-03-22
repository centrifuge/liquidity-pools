// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import "forge-std/Test.sol";
import {IERC20} from "src/interfaces/IERC20.sol";
import {BitmapLib} from "src/libraries/BitmapLib.sol";

contract BitmapLibTest is Test {
    using BitmapLib for uint256;

    function testSetBit(bool[] memory input) public {
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
}
