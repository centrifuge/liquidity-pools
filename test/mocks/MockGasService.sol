// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import "test/mocks/Mock.sol";

contract MockGasService is Mock {
    function estimate(bytes calldata) public view returns (uint256) {
        return values_uint256_return["estimate"];
    }
}
