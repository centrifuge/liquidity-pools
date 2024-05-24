// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import "test/mocks/Mock.sol";
import "src/token/RestrictionManager.sol";

contract MockRestrictionManagerFactory is Mock {
    function newRestrictionManager(
        uint8 restrictionSet,
        address token,
        address[] calldata /* restrictionManagerWards */
    ) public returns (address) {
        values_uint8["restrictionSet"] = restrictionSet;
        RestrictionManager restrictionManager = new RestrictionManager(token);
        restrictionManager.rely(msg.sender);
        return address(restrictionManager);
    }
}
