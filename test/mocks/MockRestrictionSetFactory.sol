// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import "test/mocks/Mock.sol";

contract MockRestrictionSetFactory is Mock {
    function newRestrictionSet(uint8 restrictionSet, address, /* token */ address[] calldata /* restrictionSetWards */ )
        public
        returns (address)
    {
        values_uint8["restrictionSet"] = restrictionSet;
        return address(0);
    }
}
