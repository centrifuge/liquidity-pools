// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import {Auth} from "./Auth.sol";
import {SafeTransferLib} from "./libraries/SafeTransferLib.sol";
import "./interfaces/IERC7540.sol";

contract CentrifugeRouter is Auth {
    event LockDepositRequest(address indexed vault, address indexed user, uint256 amount);
    event UnlockDepositRequest(address indexed vault, address indexed user);
    event ExecuteLockedDepositRequest(address indexed vault, address indexed user);

    mapping(address => mapping(address => uint256)) public lockedRequests;

    // --- Administration ---
    function recoverTokens(address token, address to, uint256 amount) external auth {
        SafeTransferLib.safeTransfer(token, to, amount);
    }

    // --- Deposit ---
    function requestDeposit(address vault, uint256 amount) external {
        IERC7540(vault).requestDeposit(amount, msg.sender, msg.sender);
    }

    function lockDepositRequest(address vault, uint256 amount) external {
        SafeTransferLib.safeTransferFrom(IERC7540(vault).asset(), msg.sender, address(this), amount);
        lockedRequests[msg.sender][vault] += amount;
        emit LockDepositRequest(vault, msg.sender, amount);
    }

    function unlockDepositRequest(address vault) external {
        uint256 lockedRequest = lockedRequests[msg.sender][vault];
        require(lockedRequest > 0, "CentrifugeRouter/user-has-no-locked-balance");
        lockedRequests[msg.sender][vault] = 0;
        SafeTransferLib.safeTransfer(IERC7540(vault).asset(), msg.sender, lockedRequest);
        emit UnlockDepositRequest(vault, msg.sender);
    }

    function executeLockedDepositRequest(address vault, address user) external {
        uint256 lockedRequest = lockedRequests[user][vault];
        require(lockedRequest > 0, "CentrifugeRouter/user-has-no-balance");
        lockedRequests[user][vault] = 0;
        IERC7540(vault).requestDeposit(lockedRequest, msg.sender, address(this));
        emit ExecuteLockedDepositRequest(vault, user);
    }

    function claimDeposit(address vault, address user) external {
        uint256 maxDeposit = IERC7540(vault).maxDeposit(user);
        require(maxDeposit > 0, "CentrifugeRouter/user-has-no-balance-to-claim");
        IERC7540(vault).deposit(maxDeposit, user, user);
    }

    // --- Redeem ---
    function requestRedeem(address vault, uint256 amount) external {
        IERC7540(vault).requestRedeem(amount, msg.sender, msg.sender);
    }

    function claimRedeem(address vault, address user) external {
        uint256 maxRedeem = IERC7540(vault).maxRedeem(user);
        require(maxRedeem > 0, "CentrifugeRouter/user-has-no-balance-to-claim");
        IERC7540(vault).redeem(maxRedeem, user, user);
    }
}
