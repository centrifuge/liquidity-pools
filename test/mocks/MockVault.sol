// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.26;

import "forge-std/Test.sol";
import "./Mock.sol";

contract MockVault is Mock {
    address public asset = makeAddr("asset");
    address public share = makeAddr("share");

    // Added to be ignored in coverage report
    function test() public {}
}
