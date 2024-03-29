// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import {Root} from "../Root.sol";
import {Auth} from "./../Auth.sol";

interface PauseAdminLike {
    function addPauser(address user) external;
    function removePauser(address user) external;
}

interface RouterAggregatorLike {
    function disputeMessageRecovery(bytes32 messageHash) external;
}

/// @title  Delayed Admin
/// @dev    Any ward on this contract can trigger
///         instantaneous pausing and unpausing
///         on the Root, as well as schedule and cancel
///         new relys through the timelock.
contract DelayedAdmin is Auth {
    Root public immutable root;
    PauseAdminLike public immutable pauseAdmin;
    RouterAggregatorLike public immutable aggregator;

    constructor(address root_, address pauseAdmin_, address aggregator_) {
        root = Root(root_);
        pauseAdmin = PauseAdminLike(pauseAdmin_);
        aggregator = RouterAggregatorLike(aggregator_);

        wards[msg.sender] = 1;
        emit Rely(msg.sender);
    }

    // --- Admin actions ---
    function pause() external auth {
        root.pause();
    }

    function unpause() external auth {
        root.unpause();
    }

    function scheduleRely(address target) external auth {
        root.scheduleRely(target);
    }

    function cancelRely(address target) external auth {
        root.cancelRely(target);
    }

    function disputeMessageRecovery(bytes32 messageHash) external auth {
        aggregator.disputeMessageRecovery(messageHash);
    }

    // --- PauseAdmin management ---
    function addPauser(address user) external auth {
        pauseAdmin.addPauser(user);
    }

    function removePauser(address user) external auth {
        pauseAdmin.removePauser(user);
    }
}
