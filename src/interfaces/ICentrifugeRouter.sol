// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.5.0;

import {Domain} from "src/interfaces/IPoolManager.sol";
import {IRecoverable} from "src/interfaces/IRoot.sol";

interface ICentrifugeRouter is IRecoverable {
    // --- Events ---
    event LockDepositRequest(
        address indexed vault, address indexed controller, address indexed owner, address sender, uint256 amount
    );
    event UnlockDepositRequest(address indexed vault, address indexed controller, address indexed receiver);
    event ExecuteLockedDepositRequest(address indexed vault, address indexed controller, address sender);

    /// @notice TODO
    function lockedRequests(address controller, address vault) external view returns (uint256 amount);

    // --- Deposit ---
    /// @notice Check `IERC7540Deposit.requestDeposit`.
    /// @dev    This adds a mandatory prepayment for all the costs that will incur during the transaction.
    ///         The caller must call `CentrifugeRouter.estimate` to get estimates how much the deposit will cost.
    ///
    /// @param  vault The vault to deposit into
    /// @param  amount Check @param IERC7540Deposit.requestDeposit.assets
    /// @param  controller Check @param IERC7540Deposit.requestDeposit.controller
    /// @param  owner Check @param IERC7540Deposit.requestDeposit.owner
    /// @param  topUpAmount Amount that covers all costs outside EVM
    function requestDeposit(address vault, uint256 amount, address controller, address owner, uint256 topUpAmount)
        external
        payable;

    /// @notice TODO
    function lockDepositRequest(address vault, uint256 amount, address controller, address owner) external payable;

    /// @notice Helper method to lock a deposit request, and enable permissionless claiming of that vault in 1 call
    function openLockDepositRequest(address vault, uint256 amount) external payable;

    /// @notice TODO
    function unlockDepositRequest(address vault, address receiver) external payable;

    /// @notice TODO
    function executeLockedDepositRequest(address vault, address controller, uint256 topUpAmount) external payable;

    /// @notice TODO
    function claimDeposit(address vault, address receiver, address controller) external payable;

    // --- Redeem ---
    /// @notice Check `IERC7540CancelDeposit.cancelDepositRequest`.
    /// @dev    This adds a mandatory prepayment for all the costs that will incur during the transaction.
    ///         The caller must call `CentrifugeRouter.estimate` to get estimates how much the deposit will cost.
    ///
    /// @param  vault The vault where the deposit was initiated
    /// @param  topUpAmount Amount that covers all costs outside EVM
    function cancelDepositRequest(address vault, uint256 topUpAmount) external payable;

    /// @notice TODO
    function claimCancelDepositRequest(address vault, address receiver, address controller) external payable;

    // --- Redeem ---
    /// @notice Check `IERC7540Redeem.requestRedeem`.
    /// @dev    This adds a mandatory prepayment for all the costs that will incur during the transaction.
    ///         The caller must call `CentrifugeRouter.estimate` to get estimates how much the deposit will cost.
    ///
    /// @param  vault The vault to deposit into
    /// @param  amount Check @param IERC7540Redeem.requestRedeem.shares
    /// @param  controller Check @param IERC7540Redeem.requestRedeem.controller
    /// @param  owner Check @param IERC7540Redeem.requestRedeem.owner
    /// @param  topUpAmount Amount that covers all costs outside EVM
    function requestRedeem(address vault, uint256 amount, address controller, address owner, uint256 topUpAmount)
        external
        payable;

    /// @notice TODO
    function claimRedeem(address vault, address receiver, address controller) external payable;

    // --- Manage permissionless claiming ---
    /// @notice Allow permissionless claiming
    function open(address vault) external;

    /// @notice Disallow permissionless claiming
    function close(address vault) external;

    /// @notice Check `IERC7540CancelRedeem.cancelRedeemRequest`.
    /// @dev    This adds a mandatory prepayment for all the costs that will incur during the transaction.
    ///         The caller must call `CentrifugeRouter.estimate` to get estimates how much the deposit will cost.
    ///
    /// @param  vault The vault where the deposit was initiated
    /// @param  topUpAmount Amount that covers all costs outside EVM
    function cancelRedeemRequest(address vault, uint256 topUpAmount) external payable;

    function claimCancelRedeemRequest(address vault, address receiver, address controller) external payable;

    // --- Transfer ---
    /// @notice Check `IPoolManager.transferAssets`.
    /// @dev    This adds a mandatory prepayment for all the costs that will incur during the transaction.
    ///         The caller must call `CentrifugeRouter.estimate` to get estimates how much the deposit will cost.
    ///
    /// @param  asset Check `IPoolManager.transferAssets.asset`
    /// @param  recipient Check `IPoolManager.transferAssets.recipient`
    /// @param  amount Check `IPoolManager.transferAssets.amount`
    /// @param  topUpAmount Amount that covers all costs outside EVM
    function transferAssets(address asset, bytes32 recipient, uint128 amount, uint256 topUpAmount) external payable;

    /// @notice This is a more friendly version where the recipient is and EVM address
    /// @dev the recipient address is padded to 32 bytes internally
    function transferAssets(address asset, address recipient, uint128 amount, uint256 topUpAmount) external payable;

    /// @notice Check `IPoolManager.transferTrancheTokens`.
    /// @dev    This adds a mandatory prepayment for all the costs that will incur during the transaction.
    ///         The caller must call `CentrifugeRouter.estimate` to get estimates how much the deposit will cost.
    ///
    /// @param  vault The vault for the corresponding tranche token
    /// @param  domain Check `IPoolManager.transferTrancheTokens.domain`
    /// @param  id Check `IPoolManager.transferTrancheTokens.destinationId`
    /// @param  recipient Check `IPoolManager.transferTrancheTokens.recipient`
    /// @param  amount Check `IPoolManager.transferTrancheTokens.amount`
    /// @param  topUpAmount Amount that covers all costs outside EVM
    function transferTrancheTokens(
        address vault,
        Domain domain,
        uint64 id,
        bytes32 recipient,
        uint128 amount,
        uint256 topUpAmount
    ) external payable;

    /// @notice This is a more friendly version where the recipient is and EVM address
    /// @dev the recipient address is padded to 32 bytes internally
    function transferTrancheTokens(
        address vault,
        Domain domain,
        uint64 chainId,
        address recipient,
        uint128 amount,
        uint256 topUpAmount
    ) external payable;

    // --- ERC20 permit ---
    /// @notice TODO
    function permit(address asset, address spender, uint256 assets, uint256 deadline, uint8 v, bytes32 r, bytes32 s)
        external
        payable;

    // --- ERC20 wrapping ---
    /// @notice TODO
    function wrap(address wrapper, uint256 amount, address receiver, address owner) external payable;

    /// @notice TODO
    function unwrap(address wrapper, uint256 amount, address receiver) external payable;

    // --- Batching ---
    /// @notice TODO
    function multicall(bytes[] memory data) external payable;

    // --- View Methods ---
    /// @notice TODO
    function getVault(uint64 poolId, bytes16 trancheId, address asset) external view returns (address);

    /// @notice TODO
    function estimate(bytes calldata payload) external view returns (uint256 amount);
}
