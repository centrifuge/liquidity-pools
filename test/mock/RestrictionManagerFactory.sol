// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import "./Mock.sol";

contract RestrictionManagerFactoryMock is Mock {
    function newRestrictionManager(
        uint8 restrictionSet,
        address, /* token */
        address[] calldata /* restrictionManagerWards */
    ) public returns (address) {
        values_uint8["restrictionSet"] = restrictionSet;
        return address(0);
    }
}
