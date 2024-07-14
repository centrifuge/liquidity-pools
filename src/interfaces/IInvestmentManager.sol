// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.5.0;

import {IMessageHandler} from "src/interfaces/gateway/IGateway.sol";
import {IRecoverable} from "src/interfaces/IRoot.sol";

/// @dev Vault orders and investment/redemption limits per user
struct InvestmentState {
    /// @dev shares that can be claimed using `mint()`
    uint128 maxMint;
    /// @dev Weighted average price of deposits, used to convert maxMint to maxDeposit
    uint256 depositPrice;
    /// @dev Currency that can be claimed using `withdraw()`
    uint128 maxWithdraw;
    /// @dev Weighted average price of redemptions, used to convert maxWithdraw to maxRedeem
    uint256 redeemPrice;
    /// @dev Remaining deposit order in assets
    uint128 pendingDepositRequest;
    /// @dev Remaining redeem order in shares
    uint128 pendingRedeemRequest;
    /// @dev Currency that can be claimed using `claimCancelDepositRequest()`
    uint128 claimableCancelDepositRequest;
    /// @dev Shares that can be claimed using `claimCancelRedeemRequest()`
    uint128 claimableCancelRedeemRequest;
    /// @dev Indicates whether the depositRequest was requested to be canceled
    bool pendingCancelDepositRequest;
    /// @dev Indicates whether the redeemRequest was requested to be canceled
    bool pendingCancelRedeemRequest;
}

interface IInvestmentManager is IMessageHandler, IRecoverable {
    // --- Events ---
    event File(bytes32 indexed what, address data);
    event TriggerRedeemRequest(
        uint64 indexed poolId, bytes16 indexed trancheId, address user, address asset, uint128 shares
    );

    /// @notice Updates contract parameters of type address.
    /// @param what The bytes32 representation of 'gateway' or 'poolManager'.
    /// @param data The new contract address.
    function file(bytes32 what, address data) external;

    // --- Outgoing message handling ---
    /// @notice Liquidity pools have to request investments from Centrifuge before
    ///         shares can be minted. The deposit requests are added to the order book
    ///         on Centrifuge. Once the next epoch is executed on Centrifuge, vaults can
    ///         proceed with share payouts in case their orders get fulfilled.
    /// @dev    The user asset amount required to fulfill the deposit request have to be locked,
    ///         even though the share payout can only happen after epoch execution.
    function requestDeposit(address vault, uint256 assets, address receiver, address owner, address source)
        external
        returns (bool);

    /// @notice Requests share redemption. Liquidity pools have to request redemptions
    ///         from Centrifuge before actual asset payouts can be done. The redemption
    ///         requests are added to the order book on Centrifuge. Once the next epoch is
    ///         executed on Centrifuge, vaults can proceed with asset payouts
    ///         in case their orders get fulfilled.
    /// @dev    The user shares required to fulfill the redemption request have to be locked,
    ///         even though the asset payout can only happen after epoch execution.
    function requestRedeem(address vault, uint256 shares, address receiver, address, /* owner */ address source)
        external
        returns (bool);

    /// @notice Requests the cancellation of a pending deposit request. Liquidity pools have to request the
    ///         cancellation of outstanding requests
    ///         from Centrifuge before actual asset can be unlocked and transferred to the owner.
    ///         While users have outstanding cancellation requests no new deposit requests can be submitted.
    ///         Once the next epoch is executed on Centrifuge, vaults can proceed with asset payouts
    ///         in case the orders could be canceled successfully.
    /// @dev    The cancellation request might fail, in case the pending deposit order already got fulfilled on
    ///         Centrifuge.
    function cancelDepositRequest(address vault, address owner, address source) external;

    /// @notice Requests the cancellation of an pending redeem request. Liquidity pools have to request the
    ///         cancellation of outstanding requests from Centrifuge before actual shares can be unlocked and
    ///         transferred to the owner.
    ///         While users have outstanding cancellation requests no new redeem requests can be submitted (exception:
    ///         trigger through governance).
    ///         Once the next epoch is executed on Centrifuge, vaults can proceed with share payouts
    ///         in case the orders could be canceled successfully.
    /// @dev    The cancellation request might fail, in case the pending redeem order already got fulfilled on
    ///         Centrifuge.
    function cancelRedeemRequest(address vault, address owner, address source) external;

    // --- Incoming message handling ---
    /// @notice Handle incoming messages from Centrifuge. Parse the function params and forward to the corresponding
    ///         handler function.
    function handle(bytes calldata message) external;

    /// @notice Fulfills pending deposit requests after successful epoch execution on Centrifuge.
    ///         The amount of shares that can be claimed by the user is minted and moved to the escrow contract.
    ///         The MaxMint bookkeeping value is updated.
    ///         The request fulfillment can also be partial.
    /// @dev    The shares in the escrow are reserved for the user and are transferred to the user on deposit
    ///         and mint calls.
    function fulfillDepositRequest(
        uint64 poolId,
        bytes16 trancheId,
        address user,
        uint128 assetId,
        uint128 assets,
        uint128 shares
    ) external;

    /// @notice Fulfills pending redeem requests after successful epoch execution on Centrifuge.
    ///         The amount of redeemed shares is burned. The amount of assets that can be claimed by the user in
    ///         return is present in the escrow contract. The MaxWithdraw bookkeeping value is updated.
    ///         The request fulfillment can also be partial.
    /// @dev    The assets in the escrow are reserved for the user and are transferred to the user on redeem
    ///         and withdraw calls.
    function fulfillRedeemRequest(
        uint64 poolId,
        bytes16 trancheId,
        address user,
        uint128 assetId,
        uint128 assets,
        uint128 shares
    ) external;

    /// @notice Fulfills deposit request cancellation after successful epoch execution on Centrifuge.
    ///         The amount of assets that can be claimed by the user is already present in the escrow contract.
    ///         Updates claimableCancelDepositRequest bookkeeping value. The cancellation order execution can also be
    ///         partial.
    /// @dev    The assets in the escrow are reserved for the user and are transferred to the user during
    ///         claimCancelDepositRequest calls.
    function fulfillCancelDepositRequest(
        uint64 poolId,
        bytes16 trancheId,
        address user,
        uint128 assetId,
        uint128 assets,
        uint128 fulfillment
    ) external;

    /// @notice Fulfills redeem request cancellation after successful epoch execution on Centrifuge.
    ///         The amount of shares that can be claimed by the user is already present in the escrow contract.
    ///         Updates claimableCancelRedeemRequest bookkeeping value. The cancellation order execution can also be
    ///         partial.
    /// @dev    The shares in the escrow are reserved for the user and are transferred to the user during
    ///         claimCancelRedeemRequest calls.
    function fulfillCancelRedeemRequest(uint64 poolId, bytes16 trancheId, address user, uint128 assetId, uint128 shares)
        external;

    /// @notice Triggers a redeem request on behalf of the user through Centrifuge governance.
    ///         This function is required for legal/compliance reasons and rare scenarios, like share contract
    ///         migrations.
    ///         Once the next epoch is executed on Centrifuge, vaults can proceed with asset payouts in case the orders
    ///         got fulfilled.
    /// @dev    The user share amount required to fulfill the redeem request has to be locked,
    ///         even though the asset payout can only happen after epoch execution.
    function triggerRedeemRequest(uint64 poolId, bytes16 trancheId, address user, uint128 assetId, uint128 shares)
        external;

    // --- View functions ---
    /// @notice Converts the assets value to share decimals.
    function convertToShares(address vault, uint256 _assets) external view returns (uint256 shares);

    /// @notice Converts the shares value to assets decimals.
    function convertToAssets(address vault, uint256 _shares) external view returns (uint256 assets);

    /// @notice Returns the max amount of assets based on the unclaimed amount of shares after at least one successful
    ///         deposit order fulfillment on Centrifuge.
    function maxDeposit(address vault, address user) external view returns (uint256);

    /// @notice Returns the max amount of shares a user can claim after at least one successful deposit order
    ///         fulfillment on Centrifuge.
    function maxMint(address vault, address user) external view returns (uint256 shares);

    /// @notice Returns the max amount of assets a user can claim after at least one successful redeem order fulfillment
    ///         on Centrifuge.
    function maxWithdraw(address vault, address user) external view returns (uint256 assets);

    /// @notice Returns the max amount of shares based on the unclaimed number of assets after at least one successful
    ///         redeem order fulfillment on Centrifuge.
    function maxRedeem(address vault, address user) external view returns (uint256 shares);

    /// @notice Indicates whether a user has pending deposit requests and returns the total asset request value.
    function pendingDepositRequest(address vault, address user) external view returns (uint256 assets);

    /// @notice Indicates whether a user has pending redeem requests and returns the total shares request value.
    function pendingRedeemRequest(address vault, address user) external view returns (uint256 shares);

    /// @notice Indicates whether a user has pending deposit request cancellations.
    function pendingCancelDepositRequest(address vault, address user) external view returns (bool isPending);

    /// @notice Indicates whether a user has pending redeem request cancellations.
    function pendingCancelRedeemRequest(address vault, address user) external view returns (bool isPending);

    /// @notice Indicates whether a user has claimable deposit requests cancellation and returns the total asset claim
    ///         value.
    function claimableCancelDepositRequest(address vault, address user) external view returns (uint256 assets);

    /// @notice Indicates whether a user has claimable redeem requests cancellation and returns the total share claim
    ///         value.
    function claimableCancelRedeemRequest(address vault, address user) external view returns (uint256 shares);

    /// @notice Returns the timestamp of the last share price update for a vault.
    function priceLastUpdated(address vault) external view returns (uint64 lastUpdated);

    // --- Vault claim functions ---
    /// @notice Processes owner's asset deposit after the epoch has been executed on Centrifuge and the deposit order
    /// has
    ///         been successfully processed (partial fulfillment possible).
    ///         Shares are transferred from the escrow to the receiver. Amount of shares is computed based of the amount
    ///         of assets and the owner's share price.
    /// @dev    The assets required to fulfill the deposit are already locked in escrow upon calling requestDeposit.
    ///         The shares required to fulfill the deposit have already been minted and transferred to the escrow on
    ///         fulfillDepositRequest.
    ///         Receiver has to pass all the share token restrictions in order to receive the shares.
    function deposit(address vault, uint256 assets, address receiver, address owner)
        external
        returns (uint256 shares);

    /// @notice Processes owner's share mint after the epoch has been executed on Centrifuge and the deposit order has
    ///         been successfully processed (partial fulfillment possible).
    ///         Shares are transferred from the escrow to the receiver. Amount of assets is computed based of the amount
    ///         of shares and the owner's share price.
    /// @dev    The assets required to fulfill the mint are already locked in escrow upon calling requestDeposit.
    ///         The shares required to fulfill the mint have already been minted and transferred to the escrow on
    ///         fulfillDepositRequest.
    ///         Receiver has to pass all the share token restrictions in order to receive the shares.
    function mint(address vault, uint256 shares, address receiver, address owner) external returns (uint256 assets);

    /// @notice Processes owner's share redemption after the epoch has been executed on Centrifuge and the redeem order
    ///         has been successfully processed (partial fulfillment possible).
    ///         Assets are transferred from the escrow to the receiver. Amount of assets is computed based of the amount
    ///         of shares and the owner's share price.
    /// @dev    The shares required to fulfill the redemption were already locked in escrow on requestRedeem and burned
    ///         on fulfillDepositRequest.
    ///         The assets required to fulfill the redemption have already been reserved in escrow on
    ///         fulfillDepositRequest.
    function redeem(address vault, uint256 shares, address receiver, address owner) external returns (uint256 assets);

    /// @notice Processes owner's asset withdrawal after the epoch has been executed on Centrifuge and the redeem order
    ///         has been successfully processed (partial fulfillment possible).
    ///         Assets are transferred from the escrow to the receiver. Amount of shares is computed based of the amount
    ///         of shares and the owner's share price.
    /// @dev    The shares required to fulfill the withdrawal were already locked in escrow on requestRedeem and burned
    ///         on fulfillDepositRequest.
    ///         The assets required to fulfill the withdrawal have already been reserved in escrow on
    ///         fulfillDepositRequest.
    function withdraw(address vault, uint256 assets, address receiver, address owner)
        external
        returns (uint256 shares);

    /// @notice Processes owner's deposit request cancellation after the epoch has been executed on Centrifuge and the
    ///          deposit order cancellation has
    ///         been successfully processed (partial fulfillment possible).
    ///         Assets are transferred from the escrow to the receiver.
    /// @dev    The assets required to fulfill the claim have already been reserved for the owner in escrow on
    ///         fulfillCancelDepositRequest.
    function claimCancelDepositRequest(address vault, address receiver, address owner)
        external
        returns (uint256 assets);

    /// @notice Processes owner's redeem request cancellation after the epoch has been executed on Centrifuge and the
    ///         redeem order cancellation has
    ///         been successfully processed (partial fulfillment possible).
    ///         Shares are transferred from the escrow to the receiver.
    /// @dev    The shares required to fulfill the claim have already been reserved for the owner in escrow on
    ///         fulfillCancelRedeemRequest.
    ///         Receiver has to pass all the share token restrictions in order to receive the shares.
    function claimCancelRedeemRequest(address vault, address receiver, address owner)
        external
        returns (uint256 shares);
}
