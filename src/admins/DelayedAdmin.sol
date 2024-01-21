// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import {Root} from "src/Root.sol";

interface SafeLike {
    function isOwner(address signer) external view returns (bool);
}

/// @title  Guardian
/// @dev    Any ward on this contract can trigger instantaneous pausing and unpausing on the
///         Root, as well as schedule and cancel new relys through the timelock of Root.
///
///         If the ward is a Safe, any individual signer on this Safe can also pause.
contract Guardian {
    Root public immutable root;
    SafeLike public immutable safe;

    constructor(address root_, address safe_) {
        root = Root(root_);
        safe = SafeLike(safe_);
    }

    modifier auth() {
        require(msg.sender == address(safe), "Guardian/not-authorized");
        _;
    }

    modifier individualOwner() {
        require(_isSafeOwner(safe, msg.sender), "Guardian/not-authorized-to-pause");
        _;
    }

    // --- Admin actions ---
    function pause() external individualOwner {
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

    // --- Helpers ---
    function _isSafeOwner(address safe, address addr) internal returns (bool) {
        try safe.isOwner(addr) returns (bool isOwner) {
            return isOwner;
        } catch {
            return false;
        }
    }
}
