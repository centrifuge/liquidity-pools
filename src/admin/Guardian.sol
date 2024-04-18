// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import {Root} from "src/Root.sol";

interface SafeLike {
    function isOwner(address signer) external view returns (bool);
}

/// @title  Guardian
/// @dev    This contract allows a Gnosis Safe to schedule and cancel new relys,
///         and unpause the protocol through the timelock of Root. Additionally,
///         it allows any owners of the safe to instantly pause the protocol.

contract Guardian {
    Root public immutable root;
    SafeLike public immutable safe;

    constructor(address root_, address safe_) {
        root = Root(root_);
        safe = SafeLike(safe_);
    }

    modifier onlySafe() {
        require(msg.sender == address(safe), "Guardian/not-an-authorized-safe");
        _;
    }

    modifier onlyOwner() {
        require(_isSafeOwner(safe, msg.sender), "Guardian/not-an-owner-of-the-authorized-safe");
        _;
    }

    // --- Admin actions ---
    function pause() external onlyOwner {
        root.pause();
    }

    function unpause() external onlySafe {
        root.unpause();
    }

    function scheduleRely(address target) external onlySafe {
        root.scheduleRely(target);
    }

    function cancelRely(address target) external onlySafe {
        root.cancelRely(target);
    }

    // --- Helpers ---
    function _isSafeOwner(SafeLike safe, address addr) internal returns (bool) {
        return safe.isOwner(addr);
        // try safe.isOwner(addr) returns (bool isOwner) {
        //     return isOwner;
        // } catch {
        //     return false;
        // }
    }
}
