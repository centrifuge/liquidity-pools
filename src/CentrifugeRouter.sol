// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import {Auth} from "src/Auth.sol";
import {MathLib} from "src/libraries/MathLib.sol";
import {SafeTransferLib} from "src/libraries/SafeTransferLib.sol";
import {IERC7540} from "src/interfaces/IERC7540.sol";
import {IERC20, IERC20Permit} from "src/interfaces/IERC20.sol";
import {IMulticall} from "src/interfaces/IMulticall.sol";
import {ICentrifugeRouter} from "src/interfaces/ICentrifugeRouter.sol";
import {IPoolManager} from "src/interfaces/IPoolManager.sol";

interface IERC20Wrapper {
    function underlying() external view returns (address);
    function depositFor(address account, uint256 value) external returns (bool);
    function withdrawTo(address account, uint256 value) external returns (bool);
}

contract CentrifugeRouter is Auth, ICentrifugeRouter {
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
    function file(bytes32 what, address data) external auth {
        if (what == "poolManager") poolManager = data;
        else revert("CentrifugeRouter/file-unrecognized-param");
        emit File(what, data);
    }

    /// @inheritdoc ICentrifugeRouter
    function recoverTokens(address token, address to, uint256 amount) external auth {
        SafeTransferLib.safeTransfer(token, to, amount);
    }

    // --- Deposit ---
    /// @inheritdoc ICentrifugeRouter
    function requestDeposit(address vault, uint256 amount, address controller, address owner) external {
        IERC7540(vault).requestDeposit(amount, controller, owner);
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
    /// @dev requires calling approveMax(asset, vault) before
    function executeLockedDepositRequest(address vault, address user) external {
        uint256 lockedRequest = lockedRequests[user][vault];
        require(lockedRequest > 0, "CentrifugeRouter/user-has-no-balance");
        lockedRequests[user][vault] = 0;
        IERC7540(vault).requestDeposit(lockedRequest, user, address(this));
        emit ExecuteLockedDepositRequest(vault, user);
    }

    /// @inheritdoc ICentrifugeRouter
    function claimDeposit(address vault, address receiver, address controller) external {
        uint256 maxDeposit = IERC7540(vault).maxDeposit(controller);
        IERC7540(vault).deposit(maxDeposit, receiver, controller);
    }

    // --- Redeem ---
    /// @inheritdoc ICentrifugeRouter
    function requestRedeem(address vault, uint256 amount, address controller, address owner) external {
        IERC7540(vault).requestRedeem(amount, controller, owner);
    }

    /// @inheritdoc ICentrifugeRouter
    function claimRedeem(address vault, address receiver, address controller) external {
        uint256 maxRedeem = IERC7540(vault).maxRedeem(controller);
        IERC7540(vault).redeem(maxRedeem, receiver, controller);
    }

    // --- ERC20 approval ---
    /// @inheritdoc ICentrifugeRouter
    function approveMax(address token, address spender) external {
        if (IERC20(token).allowance(address(this), spender) == 0) {
            SafeTransferLib.safeApprove(token, spender, type(uint256).max);
        }
    }

    function permit(address asset, uint256 assets, uint256 deadline, uint8 v, bytes32 r, bytes32 s) external {
        try IERC20Permit(asset).permit(msg.sender, address(this), assets, deadline, v, r, s) {} catch {}
    }

    // --- ERC20 wrapping ---
    /// @dev requires calling approveMax(underlying, wrapper) before
    function wrap(address wrapper, uint256 amount) external {
        address underlying = address(IERC20Wrapper(wrapper).underlying());
        amount = MathLib.min(amount, IERC20(underlying).balanceOf(address(this)));
        require(amount != 0, "CentrifugeRouter/zero-balance");
        require(IERC20Wrapper(wrapper).depositFor(msg.sender, amount), "CentrifugeRouter/deposit-for-failed");
    }

    function unwrap(address wrapper, address user, uint256 amount) external {
        require(user != address(0), "CentrifugeRouter/zero-address");
        amount = MathLib.min(amount, IERC20(wrapper).balanceOf(address(this)));
        require(amount != 0, "CentrifugeRouter/zero-balance");
        require(IERC20Wrapper(wrapper).withdrawTo(user, amount), "CentrifugeRouter/withdraw-to-failed");
    }

    // --- Batching ---
    /// @inheritdoc IMulticall
    function multicall(bytes[] calldata data) public payable override returns (bytes[] memory results) {
        results = new bytes[](data.length);
        for (uint256 i = 0; i < data.length; i++) {
            (bool success, bytes memory result) = address(this).delegatecall(data[i]);

            if (!success) {
                // Next 5 lines from https://ethereum.stackexchange.com/a/83577
                if (result.length < 68) revert();
                assembly {
                    result := add(result, 0x04)
                }
                revert(abi.decode(result, (string)));
            }

            results[i] = result;
        }
    }

    // --- View Methods ---
    /// @inheritdoc ICentrifugeRouter
    function getVault(uint64 poolId, bytes16 trancheId, address asset) external view returns (address) {
        return IPoolManager(poolManager).getVault(poolId, trancheId, asset);
    }
}
