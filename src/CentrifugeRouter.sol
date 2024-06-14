// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import {Auth} from "src/Auth.sol";
import {Multicall} from "src/Multicall.sol";
import {SafeTransferLib} from "src/libraries/SafeTransferLib.sol";
import {IERC7540Vault} from "src/interfaces/IERC7540.sol";
import {IERC20} from "src/interfaces/IERC20.sol";
import {ICentrifugeRouter} from "src/interfaces/ICentrifugeRouter.sol";
import {IPoolManager} from "src/interfaces/IPoolManager.sol";

contract CentrifugeRouter is Auth, Multicall, ICentrifugeRouter {
    address public poolManager;

    /// @inheritdoc ICentrifugeRouter
    mapping(address user => mapping(address vault => uint256 amount)) public lockedRequests;

    constructor(address poolManager_) {
        poolManager = poolManager_;

        wards[msg.sender] = 1;
        emit Rely(msg.sender);
    }

    // --- Administration ---
    /// @inheritdoc ICentrifugeRouter
    function recoverTokens(address token, address to, uint256 amount) external auth {
        SafeTransferLib.safeTransfer(token, to, amount);
    }

    /// @inheritdoc ICentrifugeRouter
    function file(bytes32 what, address data) external auth {
        if (what == "poolManager") poolManager = data;
        else revert("CentrifugeRouter/file-unrecognized-param");
        emit File(what, data);
    }

    // --- Approval ---
    /// @inheritdoc ICentrifugeRouter
    function approveVault(address vault) external {
        IERC20(IERC7540Vault(vault).asset()).approve(vault, type(uint256).max);
    }

    // --- Deposit ---
    /// @inheritdoc ICentrifugeRouter
    function requestDeposit(address vault, uint256 amount) external {
        IERC7540Vault(vault).requestDeposit(amount, msg.sender, msg.sender);
    }

    /// @inheritdoc ICentrifugeRouter
    function lockDepositRequest(address vault, uint256 amount) external {
        SafeTransferLib.safeTransferFrom(IERC7540Vault(vault).asset(), msg.sender, address(this), amount);
        lockedRequests[msg.sender][vault] += amount;
        emit LockDepositRequest(vault, msg.sender, amount);
    }

    /// @inheritdoc ICentrifugeRouter
    function unlockDepositRequest(address vault) external {
        uint256 lockedRequest = lockedRequests[msg.sender][vault];
        require(lockedRequest > 0, "CentrifugeRouter/user-has-no-locked-balance");
        lockedRequests[msg.sender][vault] = 0;
        SafeTransferLib.safeTransfer(IERC7540Vault(vault).asset(), msg.sender, lockedRequest);
        emit UnlockDepositRequest(vault, msg.sender);
    }

    /// @inheritdoc ICentrifugeRouter
    function executeLockedDepositRequest(address vault, address user) external {
        uint256 lockedRequest = lockedRequests[user][vault];
        require(lockedRequest > 0, "CentrifugeRouter/user-has-no-balance");
        lockedRequests[user][vault] = 0;
        IERC7540Vault(vault).requestDeposit(lockedRequest, user, address(this));
        emit ExecuteLockedDepositRequest(vault, user);
    }

    /// @inheritdoc ICentrifugeRouter
    function claimDeposit(address vault, address user) external {
        uint256 maxDeposit = IERC7540Vault(vault).maxDeposit(user);
        IERC7540Vault(vault).deposit(maxDeposit, user, user);
    }

    // --- Redeem ---
    /// @inheritdoc ICentrifugeRouter
    function requestRedeem(address vault, uint256 amount) external {
        IERC7540Vault(vault).requestRedeem(amount, msg.sender, msg.sender);
    }

    /// @inheritdoc ICentrifugeRouter
    function claimRedeem(address vault, address user) external {
        uint256 maxRedeem = IERC7540Vault(vault).maxRedeem(user);
        IERC7540Vault(vault).redeem(maxRedeem, user, user);
    }

    // --- View Methods ---
    /// @inheritdoc ICentrifugeRouter
    function getVault(uint64 poolId, bytes16 trancheId, address asset) external view returns (address) {
        return IPoolManager(poolManager).getVault(poolId, trancheId, asset);
    }
}
