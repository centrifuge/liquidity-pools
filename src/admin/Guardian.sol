// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import {Root} from "src/Root.sol";
import {IGuardian} from "src/interfaces/IGuardian.sol";

interface SafeLike {
    function getOwners() external view returns (address[] memory);
    function isOwner(address signer) external view returns (bool);
    function getThreshold() external view returns (uint256);
}

interface RouterAggregatorLike {
    function disputeMessageRecovery(bytes32 messageHash) external;
}

/// @title  Guardian
/// @dev    This contract allows a Gnosis Safe to schedule and cancel new relys,
///         and unpause the protocol through the timelock of Root. Additionally,
///         it allows any owners of the safe to instantly pause the protocol.

contract Guardian is IGuardian {
    Root public immutable root;
    SafeLike public immutable safe;
    RouterAggregatorLike public immutable aggregator;

    constructor(address safe_, address root_, address aggregator_) {
        root = Root(root_);
        safe = SafeLike(safe_);
        aggregator = RouterAggregatorLike(aggregator_);
    }

    modifier onlySafe() {
        require(msg.sender == address(safe), "Guardian/not-an-authorized-safe");
        _;
    }

    modifier onlySafeOrOwner() {
        require(
            msg.sender == address(safe) || _isSafeOwner(safe, msg.sender),
            "Guardian/not-an-owner-of-the-authorized-safe"
        );
        _;
    }

    // --- Admin actions ---
    /// @inheritdoc IGuardian
    function pause() external onlySafeOrOwner {
        root.pause();
    }

    /// @inheritdoc IGuardian
    function unpause() external onlySafe {
        root.unpause();
    }

    /// @inheritdoc IGuardian
    function scheduleRely(address target) external onlySafe {
        root.scheduleRely(target);
    }

    /// @inheritdoc IGuardian
    function cancelRely(address target) external onlySafe {
        root.cancelRely(target);
    }

    /// @inheritdoc IGuardian
    function disputeMessageRecovery(bytes32 messageHash) external onlySafe {
        aggregator.disputeMessageRecovery(messageHash);
    }

    // --- Helpers ---
    function _isSafeOwner(SafeLike adminSafe, address addr) internal returns (bool) {
        try adminSafe.isOwner(addr) returns (bool isOwner) {
            return isOwner;
        } catch {
            return false;
        }
    }
}
