// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import {Root} from "src/Root.sol";
import {IGuardian} from "src/interfaces/IGuardian.sol";

interface SafeLike {
    function isOwner(address signer) external view returns (bool);
}

interface GatewayLike {
    function disputeMessageRecovery(bytes32 messageHash) external;
}

contract Guardian is IGuardian {
    Root public immutable root;
    SafeLike public immutable safe;
    GatewayLike public immutable gateway;

    constructor(address safe_, address root_, address gateway_) {
        root = Root(root_);
        safe = SafeLike(safe_);
        gateway = GatewayLike(gateway_);
    }

    modifier onlySafe() {
        require(msg.sender == address(safe), "Guardian/not-the-authorized-safe");
        _;
    }

    modifier onlySafeOrOwner() {
        require(
            msg.sender == address(safe) || _isSafeOwner(msg.sender), "Guardian/not-the-authorized-safe-or-its-owner"
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
        gateway.disputeMessageRecovery(messageHash);
    }

    // --- Helpers ---
    function _isSafeOwner(address addr) internal view returns (bool) {
        try safe.isOwner(addr) returns (bool isOwner) {
            return isOwner;
        } catch {
            return false;
        }
    }
}
