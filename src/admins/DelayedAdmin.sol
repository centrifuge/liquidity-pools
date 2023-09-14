// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import {Root} from "../Root.sol";
import {Auth} from "./../util/Auth.sol";

interface PauseAdminLike {
    function addPauser(address user) external;
    function removePauser(address user) external;
}

/// @title  Delayed Admin
/// @dev    Any ward on this contract can trigger
///         instantaneous pausing and unpausing
///         on the Root, as well as schedule and cancel
///         new relys through the timelock.
contract DelayedAdmin is Auth {
    Root public immutable root;

    constructor(address root_) {
        root = Root(root_);

        wards[msg.sender] = 1;
        emit Rely(msg.sender);
    }

    // --- Admin actions ---
    function pause() public auth {
        root.pause();
    }

    function unpause() public auth {
        root.unpause();
    }

    function scheduleRely(address target) public auth {
        root.scheduleRely(target);
    }

    function cancelRely(address target) public auth {
        root.cancelRely(target);
    }

    // --- PauseAdmin management ---
    function addPauser(address pauseContract, address user) public auth {
        PauseAdminLike(pauseContract).addPauser(user);
    }

    function removePauser(address pauseContract, address user) public auth {
        PauseAdminLike(pauseContract).removePauser(user);
    }
}
