// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import "src/token/RestrictionManager.sol";

contract MigratedRestrictionManager is RestrictionManager {
    constructor(address token_) RestrictionManager(token_) {}
}
