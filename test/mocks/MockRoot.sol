// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import "test/mocks/Mock.sol";

contract MockRoot is Mock {
    function endorsed(address user) public view returns (bool) {
        return values_bool_return["endorsed_user"];
    }
}
