// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.26;

import "forge-std/Test.sol";
import "./Mock.sol";

contract MockVault is Mock {
    address public immutable asset;
    address public immutable share;

    constructor(address asset_, address share_) {
        asset = asset_;
        share = share_;
    }

    // Added to be ignored in coverage report
    function test() public {}
}
