// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.7.6;
pragma abicoder v2;

import {TypedMemView} from "memview-sol/TypedMemView.sol";
import {ConnectorMessages} from "src/Messages.sol";
import "forge-std/Test.sol";

/// A place for Misc-like tests
contract MiscTest is Test {
    function testCallIndex() public {
        assertEq(abi.encodePacked(uint8(uint256(108)), uint8(uint256(99))), hex"6c63");
    }
}
