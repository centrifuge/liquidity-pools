// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import "./Mock.sol";
import "../../src/token/RestrictionManager.sol";

contract RestrictionManagerMock is RestrictionManager, Mock {
    constructor(address token_) RestrictionManager(token_) {}
}
