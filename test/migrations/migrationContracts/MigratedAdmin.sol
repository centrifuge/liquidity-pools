// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import "src/admins/DelayedAdmin.sol";
import "src/admins/PauseAdmin.sol";

contract MigratedDelayedAdmin is DelayedAdmin {
    constructor(address root_, address pauseAdmin_) DelayedAdmin(root_, pauseAdmin_) {}
}

contract MigratedPauseAdmin is PauseAdmin {
    constructor(address root_) PauseAdmin(root_) {}
}
