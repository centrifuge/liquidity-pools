// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import {Auth} from "src/Auth.sol";
import {IERC7540} from "src/interfaces/IERC7540.sol";
import {SafeTransferLib} from "src/libraries/SafeTransferLib.sol";
import {ICentrifugeRouter} from "src/interfaces/ICentrifugeRouter.sol";

contract CentrifugeRouter is Auth, ICentrifugeRouter {
    /// @inheritdoc ICentrifugeRouter
    mapping(address user => mapping(address vault => uint256 amount)) public lockedRequests;

    // --- Administration ---
    /// @inheritdoc ICentrifugeRouter
    function recoverTokens(address token, address to, uint256 amount) external auth {
        SafeTransferLib.safeTransfer(token, to, amount);
    }

    // --- Deposit ---
    /// @inheritdoc ICentrifugeRouter
    function requestDeposit(address vault, uint256 amount) external {
        IERC7540(vault).requestDeposit(amount, msg.sender, msg.sender);
    }

    /// @inheritdoc ICentrifugeRouter
    function lockDepositRequest(address vault, uint256 amount) external {
        SafeTransferLib.safeTransferFrom(IERC7540(vault).asset(), msg.sender, address(this), amount);
        lockedRequests[msg.sender][vault] += amount;
        emit LockDepositRequest(vault, msg.sender, amount);
    }

    /// @inheritdoc ICentrifugeRouter
    function unlockDepositRequest(address vault) external {
        uint256 lockedRequest = lockedRequests[msg.sender][vault];
        require(lockedRequest > 0, "CentrifugeRouter/user-has-no-locked-balance");
        lockedRequests[msg.sender][vault] = 0;
        SafeTransferLib.safeTransfer(IERC7540(vault).asset(), msg.sender, lockedRequest);
        emit UnlockDepositRequest(vault, msg.sender);
    }

    /// @inheritdoc ICentrifugeRouter
    function executeLockedDepositRequest(address vault, address user) external {
        uint256 lockedRequest = lockedRequests[user][vault];
        require(lockedRequest > 0, "CentrifugeRouter/user-has-no-balance");
        lockedRequests[user][vault] = 0;
        IERC7540(vault).requestDeposit(lockedRequest, msg.sender, address(this));
        emit ExecuteLockedDepositRequest(vault, user);
    }

    /// @inheritdoc ICentrifugeRouter
    function claimDeposit(address vault, address user) external {
        uint256 maxDeposit = IERC7540(vault).maxDeposit(user);
        require(maxDeposit > 0, "CentrifugeRouter/user-has-no-balance-to-claim");
        IERC7540(vault).deposit(maxDeposit, user, user);
    }

    // --- Redeem ---
    /// @inheritdoc ICentrifugeRouter
    function requestRedeem(address vault, uint256 amount) external {
        IERC7540(vault).requestRedeem(amount, msg.sender, msg.sender);
    }

    /// @inheritdoc ICentrifugeRouter
    function claimRedeem(address vault, address user) external {
        uint256 maxRedeem = IERC7540(vault).maxRedeem(user);
        require(maxRedeem > 0, "CentrifugeRouter/user-has-no-balance-to-claim");
        IERC7540(vault).redeem(maxRedeem, user, user);
    }
}
