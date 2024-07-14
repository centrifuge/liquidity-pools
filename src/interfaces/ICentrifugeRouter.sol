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

    /// @notice Check how much of the `vault`'s asset is locked for the current `controller`.
    /// @dev    This is a getter method
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

    /// @notice Locks `amount` of `vault`'s asset in an escrow before actually sending a deposit LockDepositRequest
    ///         There are users that would like to interact with the protocol but haven't passed KYC yet. They can
    ///         lock the funds they would like to deposit beforehand. Once the KYC is passed, anyone can deposit on
    /// their behalf
    ///         by calling `executeLockedDepositRequest`.
    ///
    ///
    ///         Example: DAO with onchain governance, that wants to invest their treasury (aka a Prime user)
    ///             The process that doesn't include calling this method is as follows:
    ///
    ///                 1. The DAO signs the legal agreements for the pool => no onchain action,
    ///                    but only after this the issuer can call update_member to add them as a whitelisted investor
    ///                 2. Call `requestDeposit` to lock funds
    ///                 3. After the pool has fulfilled their request, call `deposit` to claim their tranche tokens
    ///
    ///
    ///             With the new router function the steps are as follows:
    ///
    ///                 1. DAO signs the legal agreement + calls  `lockDepositRequest`  in 1 governance proposal
    ///
    ///                 2. Issuer then whitelists them, then calls `executeLockDepositFunds` for them,
    ///                    then fulfills the request, then calls `claimDeposit` for them
    ///
    /// @dev    For initial interaction better use `openLockDepositRequest` which includes some of the message calls
    /// that the caller
    ///         must do execute before calling `lockDepositRequest`
    ///
    /// @param  vault The address of the vault to invest in
    /// @param  amount Amount to invest
    /// @param  controller Address of the owner of the position
    /// @param  owner Where the  funds to be deposited will be take from
    function lockDepositRequest(address vault, uint256 amount, address controller, address owner) external payable;

    /// @notice Helper method to lock a deposit request, and enable permissionless claiming of that vault in 1 call.
    /// @dev    It starts interaction with the vault by calling `open`.
    ///         If `vault`'s underlying asset is a wrapped one, there is a `wrap` message call on the deposited asset
    ///         beforehand.
    /// @param  vault Address of the vault
    /// @param  amount Amount to be deposited
    function openLockDepositRequest(address vault, uint256 amount) external payable;

    /// @notice Unlocks all deposited assets of the current caller for a given vault
    ///
    /// @param  vault Address of the vault for which funds were locked
    /// @param  receiver Address of the received of the unlocked funds
    function unlockDepositRequest(address vault, address receiver) external payable;

    /// @notice After the controller being KYC approved, anyone can call this method and
    ///         actually request a deposit with the locked funds on the behalf of the `controller`
    /// @param  vault The vault for which funds are locked
    /// @param  controller Owner of the deposit position
    /// @param  topUpAmount Amount that covers all costs outside EVM
    function executeLockedDepositRequest(address vault, address controller, uint256 topUpAmount) external payable;

    /// @notice Check IERC7540Deposit.mint
    /// @param  vault Address of the vault
    /// @param  receiver Check IERC7540Deposit.mint.receiver
    /// @param  controller Check IERC7540Deposit.mint.owner
    function claimDeposit(address vault, address receiver, address controller) external payable;

    // --- Redeem ---
    /// @notice Check `IERC7540CancelDeposit.cancelDepositRequest`.
    /// @dev    This adds a mandatory prepayment for all the costs that will incur during the transaction.
    ///         The caller must call `CentrifugeRouter.estimate` to get estimates how much the deposit will cost.
    ///
    /// @param  vault The vault where the deposit was initiated
    /// @param  topUpAmount Amount that covers all costs outside EVM
    function cancelDepositRequest(address vault, uint256 topUpAmount) external payable;

    /// @notice Check IERC7540CancelDeposit.claimCancelDepositRequest
    ///
    /// @param  vault Address of the vault
    /// @param  receiver Check  IERC7540CancelDeposit.claimCancelDepositRequest.receiver
    /// @param  controller Check  IERC7540CancelDeposit.claimCancelDepositRequest.controller
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

    /// @notice Check IERC7575.withdraw
    /// @dev    If the underlying vault asset is a wrapped one,
    ///         `CentrifugeRouter.unwrap` is called and the unwrapped
    ///         asset is sent to the receiver
    /// @param  vault Address of the vault
    /// @param  receiver Check IERC7575.withdraw.receiver
    /// @param  controller Check IERC7575.withdraw.owner
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

    /// @notice Check IERC7540CancelRedeem.claimableCancelRedeemRequest
    ///
    /// @param  vault Address of the vault
    /// @param  receiver Check  IERC7540CancelRedeem.claimCancelRedeemRequest.receiver
    /// @param  controller Check  IERC7540CancelRedeem.claimCancelRedeemRequest.controller
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
    /// @dev    The recipient address is padded to 32 bytes internally
    function transferTrancheTokens(
        address vault,
        Domain domain,
        uint64 chainId,
        address recipient,
        uint128 amount,
        uint256 topUpAmount
    ) external payable;

    // --- ERC20 permit ---
    /// @notice Check IERC20.permit
    function permit(address asset, address spender, uint256 assets, uint256 deadline, uint8 v, bytes32 r, bytes32 s)
        external
        payable;

    // --- ERC20 wrapping ---
    /// @notice There are vault which underlying asset is actuall a wrapped one.
    ///
    /// @param  wrapper The address of the wrapper
    /// @param  amount  Amount to be wrapped
    /// @param  receiver Receiver of the wrapped tokens
    /// @param  owner The address from which `amount` is taken from
    function wrap(address wrapper, uint256 amount, address receiver, address owner) external payable;

    /// @notice There are vault which underlying asset is actuall a wrapped one.
    /// @dev    Currently only wrapped tokens where CentrifugeRouter is the owner can be unwrapped
    ///         No unwrapping for 3rd parties is supported.
    /// @param  wrapper The address of the wrapper
    /// @param  amount  Amount to be wrapped
    /// @param  receiver Receiver of the unwrapped tokens
    function unwrap(address wrapper, uint256 amount, address receiver) external payable;

    // --- Batching ---
    /// @notice Allows caller to execute multiple ( batched ) messages calls in one transaction.
    /// @dev    Messages calls that can be executed are only part of the CentrifugeRouter itself.
    ///         No reentrat execution is allowed.
    ///         In order to provide the correct value for functions that require top up,
    ///         the caller must estimate separate, in advance, how much each of the message call will cost.
    ///         The `msg.value` when calling this method must be the sum of all estimates.
    ///
    ///         Example: An investor would like to make 2 consequetive deposit requests in a single batch.
    ///         address investor            = // Investor's address
    ///         address vault               = // Vault's address
    ///         uint256 amount1             = 100 * 10 ** 18
    ///         uint256 amount2             = 50 * 10 ** 18
    ///         uint256 requestDepositCost  = 10 gwei
    ///
    ///         address router              = // CentrifugeRouter's address
    ///
    ///         bytes[] memory calls = new bytes[](2);
    ///         calls[0] = abi.encodeWithSelector(
    ///             router.requestDeposit.selector, vault, amount1, investor, investor, requestDepositCost
    ///         };
    ///         calls[1] = abi.encodeWithSelector(
    ///             router.requestDeposit.selector, vault, amount2, investor, investor, requestDepositCost
    ///         };
    ///         uint256 msgValue = 2 * requestDepositCost;

    ///         router.multical{value: msgValue}(calls);
    ///
    ///         The `msg.value` MUST be at least 20 gwei. `multicall{value: 20 gwei}()`
    /// @param  data An array of all encoded messages calls and their arguments
    function multicall(bytes[] memory data) external payable;

    // --- View Methods ---
    /// @notice Check IPoolManager.getVault
    function getVault(uint64 poolId, bytes16 trancheId, address asset) external view returns (address);

    /// @notice Check IGateway.estimate
    function estimate(bytes calldata payload) external view returns (uint256 amount);
}
