// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import {Auth} from "src/Auth.sol";
import {IERC7540} from "src/interfaces/IERC7540.sol";
import {IERC20} from "src/interfaces/IERC20.sol";
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
        requestDeposit(vault, amount, msg.sender);
    }

    /// @inheritdoc ICentrifugeRouter
    function requestDeposit(address vault, uint256 amount, address user) public {
        SafeTransferLib.safeTransferFrom(IERC7540(vault).asset(), user, address(this), amount);
        IERC20(IERC7540(vault).asset()).approve(vault, amount);
        IERC7540(vault).requestDeposit(amount, user, address(this));
    }

    /// @inheritdoc ICentrifugeRouter
    function lockDepositRequest(address vault, uint256 amount) external {
        lockDepositRequest(vault, amount, msg.sender);
    }

    /// @inheritdoc ICentrifugeRouter
    function lockDepositRequest(address vault, uint256 amount, address user) public {
        SafeTransferLib.safeTransferFrom(IERC7540(vault).asset(), user, address(this), amount);
        lockedRequests[user][vault] += amount;
        emit LockDepositRequest(vault, user, amount);
    }

    /// @inheritdoc ICentrifugeRouter
    function unlockDepositRequest(address vault) external {
        unlockDepositRequest(vault, msg.sender);
    }

    /// @inheritdoc ICentrifugeRouter
    function unlockDepositRequest(address vault, address user) public {
        uint256 lockedRequest = lockedRequests[user][vault];
        require(lockedRequest > 0, "CentrifugeRouter/user-has-no-locked-balance");
        lockedRequests[user][vault] = 0;
        SafeTransferLib.safeTransfer(IERC7540(vault).asset(), user, lockedRequest);
        emit UnlockDepositRequest(vault, user);
    }

    /// @inheritdoc ICentrifugeRouter
    function executeLockedDepositRequest(address vault, address user) external {
        uint256 lockedRequest = lockedRequests[user][vault];
        require(lockedRequest > 0, "CentrifugeRouter/user-has-no-balance");
        lockedRequests[user][vault] = 0;
        IERC20(IERC7540(vault).asset()).approve(vault, lockedRequest);
        IERC7540(vault).requestDeposit(lockedRequest, user, address(this));
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
        requestRedeem(vault, amount, msg.sender);
    }
    /// @inheritdoc ICentrifugeRouter

    function requestRedeem(address vault, uint256 amount, address user) public {
        IERC7540(vault).requestRedeem(amount, user, user);
    }

    /// @inheritdoc ICentrifugeRouter
    function claimRedeem(address vault, address user) external {
        uint256 maxRedeem = IERC7540(vault).maxRedeem(user);
        require(maxRedeem > 0, "CentrifugeRouter/user-has-no-balance-to-claim");
        IERC7540(vault).redeem(maxRedeem, user, user);
    }
}
