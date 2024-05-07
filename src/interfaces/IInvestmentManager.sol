// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.5.0;

/// @dev Vault orders and investment/redemption limits per user
struct Request {
    /// @dev Tranche tokens that can be claimed using `mint()`
    uint128 maxMint;
    /// @dev Weighted average price of deposits, used to convert maxMint to maxDeposit
    uint256 depositPrice;
    /// @dev Currency that can be claimed using `withdraw()`
    uint128 maxWithdraw;
    /// @dev Weighted average price of redemptions, used to convert maxWithdraw to maxRedeem
    uint256 redeemPrice;
    /// @dev Remaining invest (deposit) order in assets
    uint128 pendingDeposit;
    /// @dev Remaining redeem order in assets
    uint128 pendingRedeem;
    /// @dev Currency that can be claimed using `claimCancelDepositRequest()`
    uint128 claimableCancelDeposit;
    /// @dev Tranche tokens that can be claimed using `claimCancelRedeemRequest()`
    uint128 claimableCancelRedeem;
    /// @dev Whether the deposit request was requested to be cancelled
    bool pendingCancelDeposit;
    /// @dev Whether the redeem request was requested to be cancelled
    bool pendingCancelRedeem;
    ///@dev Flag whether this user has ever interacted with this vault
    bool exists;
}

interface IInvestmentManager {
    // --- Events ---
    event File(bytes32 indexed what, address data);
    event TriggerRedeemRequest(
        uint64 indexed poolId, bytes16 indexed trancheId, address user, address asset, uint128 shares
    );

    /// @notice TODO
    function file(bytes32 what, address data) external;

    /// @notice TODO
    function recoverTokens(address token, address to, uint256 amount) external;

    // --- Outgoing message handling ---
    /// @notice Liquidity pools have to request investments from Centrifuge before
    ///         tranche tokens can be minted. The deposit requests are added to the order book
    ///         on Centrifuge. Once the next epoch is executed on Centrifuge, vaults can
    ///         proceed with tranche token payouts in case their orders got fulfilled.
    /// @dev    The user asset amount required to fulfill the deposit request have to be locked,
    ///         even though the tranche token payout can only happen after epoch execution.
    function requestDeposit(address vault, uint256 assets, address receiver, address owner) external returns (bool);

    /// @notice Request tranche token redemption. Liquidity pools have to request redemptions
    ///         from Centrifuge before actual asset payouts can be done. The redemption
    ///         requests are added to the order book on Centrifuge. Once the next epoch is
    ///         executed on Centrifuge, vaults can proceed with asset payouts
    ///         in case their orders got fulfilled.
    /// @dev    The user tranche tokens required to fulfill the redemption request have to be locked,
    ///         even though the asset payout can only happen after epoch execution.
    function requestRedeem(address vault, uint256 shares, address receiver, address /* owner */ )
        external
        returns (bool);

    /// @notice TODO
    function cancelDepositRequest(address vault, address owner) external;

    /// @notice TODO
    function cancelRedeemRequest(address vault, address owner) external;

    // --- Incoming message handling ---
    /// @notice TODO
    function handle(bytes calldata message) external;

    /// @notice TODO
    function fulfillDepositRequest(
        uint64 poolId,
        bytes16 trancheId,
        address user,
        uint128 assetId,
        uint128 assets,
        uint128 shares,
        uint128 fulfillment
    ) external;

    /// @notice TODO
    function fulfillRedeemRequest(
        uint64 poolId,
        bytes16 trancheId,
        address user,
        uint128 assetId,
        uint128 assets,
        uint128 shares
    ) external;

    /// @notice TODO
    function fulfillCancelDepositRequest(
        uint64 poolId,
        bytes16 trancheId,
        address user,
        uint128 assetId,
        uint128 assets,
        uint128 fulfillment
    ) external;

    /// @dev Compared to handleFulfilledCancelDepositRequest, there is no
    ///      transfer of asset in this function because they
    ///      can stay in the Escrow, ready to be claimed on deposit/mint.
    function fulfillCancelRedeemRequest(
        uint64 poolId,
        bytes16 trancheId,
        address user,
        uint128 assetId,
        uint128 shares,
        uint128 fulfillment
    ) external;

    /// @notice TODO
    function triggerRedeemRequest(uint64 poolId, bytes16 trancheId, address user, uint128 assetId, uint128 shares)
        external;

    // --- View functions ---
    /// @notice TODO
    function convertToShares(address vault, uint256 _assets) external view returns (uint256 shares);

    /// @notice TODO
    function convertToAssets(address vault, uint256 _shares) external view returns (uint256 assets);

    /// @notice TODO
    function maxDeposit(address vault, address user) external view returns (uint256);

    /// @notice TODO
    function maxMint(address vault, address user) external view returns (uint256 shares);

    /// @notice TODO
    function maxWithdraw(address vault, address user) external view returns (uint256 assets);

    /// @notice TODO
    function maxRedeem(address vault, address user) external view returns (uint256 shares);

    /// @notice TODO
    function pendingDepositRequest(address vault, address user) external view returns (uint256 assets);

    /// @notice TODO
    function pendingRedeemRequest(address vault, address user) external view returns (uint256 shares);

    /// @notice TODO
    function pendingCancelDepositRequest(address vault, address user) external view returns (bool isPending);

    /// @notice TODO
    function pendingCancelRedeemRequest(address vault, address user) external view returns (bool isPending);

    /// @notice TODO
    function claimableCancelDepositRequest(address vault, address user) external view returns (uint256 assets);

    /// @notice TODO
    function claimableCancelRedeemRequest(address vault, address user) external view returns (uint256 shares);

    /// @notice TODO
    function priceLastUpdated(address vault) external view returns (uint64 lastUpdated);

    // --- Vault claim functions ---
    /// @notice Processes owner's asset deposit / investment after the epoch has been executed on Centrifuge.
    ///         The asset required to fulfill the invest order is already locked in escrow upon calling
    ///         requestDeposit.
    function deposit(address vault, uint256 assets, address receiver, address owner)
        external
        returns (uint256 shares);

    /// @notice Processes owner's asset deposit / investment after the epoch has been executed on Centrifuge.
    ///         The asset required to fulfill the invest order is already locked in escrow upon calling
    ///         requestDeposit.
    function mint(address vault, uint256 shares, address receiver, address owner) external returns (uint256 assets);

    /// @dev    Processes owner's tranche Token redemption after the epoch has been executed on Centrifuge.
    ///         The shares required to fulfill the redemption order was already locked in escrow
    ///         upon calling requestRedeem.
    function redeem(address vault, uint256 shares, address receiver, address owner) external returns (uint256 assets);

    /// @dev    Processes owner's tranche token redemption after the epoch has been executed on Centrifuge.
    ///         The shares required to fulfill the redemption order was already locked in escrow
    ///         upon calling requestRedeem.
    function withdraw(address vault, uint256 assets, address receiver, address owner)
        external
        returns (uint256 shares);

    /// @notice TODO
    function claimCancelDepositRequest(address vault, address receiver, address owner)
        external
        returns (uint256 assets);

    /// @notice TODO
    function claimCancelRedeemRequest(address vault, address receiver, address owner)
        external
        returns (uint256 shares);
}
