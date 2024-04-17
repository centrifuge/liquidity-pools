// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import {Auth} from "./Auth.sol";
import {CastLib} from "./libraries/CastLib.sol";
import {MathLib} from "./libraries/MathLib.sol";
import {SafeTransferLib} from "./libraries/SafeTransferLib.sol";
import {MessagesLib} from "./libraries/MessagesLib.sol";
import {BytesLib} from "./libraries/BytesLib.sol";

interface GatewayLike {
    function send(bytes memory message) external;
}

interface ERC20Like {
    function approve(address token, address spender, uint256 value) external;
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function balanceOf(address user) external view returns (uint256);
    function decimals() external view returns (uint8);
    function mint(address, uint256) external;
    function burn(address, uint256) external;
}

interface TrancheTokenLike is ERC20Like {
    function checkTransferRestriction(address from, address to, uint256 value) external view returns (bool);
}

interface VaultLike is ERC20Like {
    function poolId() external view returns (uint64);
    function trancheId() external view returns (bytes16);
    function asset() external view returns (address);
    function share() external view returns (address);
    function emitDepositClaimable(address owner, uint256 assets, uint256 shares) external;
    function emitRedeemClaimable(address owner, uint256 assets, uint256 shares) external;
}

interface AuthTransferLike {
    function authTransferFrom(address from, address to, uint256 amount) external returns (bool);
}

interface PoolManagerLike {
    function assetIdToAddress(uint128 assetId) external view returns (address);
    function currencyAddressToId(address addr) external view returns (uint128);
    function getTrancheToken(uint64 poolId, bytes16 trancheId) external view returns (address);
    function getTrancheTokenPrice(uint64 poolId, bytes16 trancheId, address currencyAddress)
        external
        view
        returns (uint128 price, uint64 computedAt);
    function getLiquidityPool(uint64 poolId, bytes16 trancheId, uint128 assetId) external view returns (address);
    function isAllowedAsInvestmentCurrency(uint64 poolId, address currencyAddress) external view returns (bool);
}

/// @dev Liquidity Pool orders and investment/redemption limits per user
struct InvestmentState {
    /// @dev Tranche tokens that can be claimed using `mint()`
    uint128 maxMint;
    /// @dev Weighted average price of deposits, used to convert maxMint to maxDeposit
    uint256 depositPrice;
    /// @dev Currency that can be claimed using `withdraw()`
    uint128 maxWithdraw;
    /// @dev Weighted average price of redemptions, used to convert maxWithdraw to maxRedeem
    uint256 redeemPrice;
    /// @dev Remaining invest (deposit) order in currency
    uint128 pendingDepositRequest;
    /// @dev Remaining redeem order in currency
    uint128 pendingRedeemRequest;
    /// @dev Currency that can be claimed using `claimCancelDepositRequest()`
    uint128 claimableCancelDepositRequest;
    /// @dev Tranche tokens that can be claimed using `claimCancelRedeemRequest()`
    uint128 claimableCancelRedeemRequest;
    /// @dev Whether the depositRequest was requested to be cancelled
    bool pendingCancelDepositRequest;
    /// @dev Whether the redeemRequest was requested to be cancelled
    bool pendingCancelRedeemRequest;
    ///@dev Flag whether this user has ever interacted with this liquidity pool
    bool exists;
}

/// @title  Investment Manager
/// @notice This is the main contract LiquidityPools interact with for
///         both incoming and outgoing investment transactions.
contract InvestmentManager is Auth {
    using BytesLib for bytes;
    using MathLib for uint256;
    using CastLib for *;

    /// @dev Prices are fixed-point integers with 18 decimals
    uint8 internal constant PRICE_DECIMALS = 18;

    address public immutable escrow;

    GatewayLike public gateway;
    PoolManagerLike public poolManager;

    mapping(address vault => mapping(address investor => InvestmentState)) public investments;

    // --- Events ---
    event File(bytes32 indexed what, address data);
    event TriggerIncreaseRedeemOrder(
        uint64 indexed poolId, bytes16 indexed trancheId, address user, address currency, uint128 shares
    );

    constructor(address escrow_) {
        escrow = escrow_;

        wards[msg.sender] = 1;
        emit Rely(msg.sender);
    }

    // --- Administration ---
    function file(bytes32 what, address data) external auth {
        if (what == "gateway") gateway = GatewayLike(data);
        else if (what == "poolManager") poolManager = PoolManagerLike(data);
        else revert("InvestmentManager/file-unrecognized-param");
        emit File(what, data);
    }

    function recoverTokens(address token, address to, uint256 amount) external auth {
        SafeTransferLib.safeTransfer(token, to, amount);
    }

    // --- Outgoing message handling ---
    /// @notice Liquidity pools have to request investments from Centrifuge before
    ///         tranche tokens can be minted. The deposit requests are added to the order book
    ///         on Centrifuge. Once the next epoch is executed on Centrifuge, liquidity pools can
    ///         proceed with tranche token payouts in case their orders got fulfilled.
    /// @dev    The user currency amount required to fulfill the deposit request have to be locked,
    ///         even though the tranche token payout can only happen after epoch execution.
    function requestDeposit(address vault, uint256 assets, address receiver, address owner)
        public
        auth
        returns (bool)
    {
        VaultLike lPool = VaultLike(vault);
        uint128 _assets = assets.toUint128();
        require(_assets != 0, "InvestmentManager/zero-amount-not-allowed");

        uint64 poolId = lPool.poolId();
        address asset = lPool.asset();
        require(poolManager.isAllowedAsInvestmentCurrency(poolId, asset), "InvestmentManager/currency-not-allowed");

        require(_checkTransferRestriction(vault, address(0), owner, 0), "InvestmentManager/owner-is-restricted");
        require(
            _checkTransferRestriction(vault, address(0), receiver, convertToShares(vault, assets)),
            "InvestmentManager/transfer-not-allowed"
        );

        InvestmentState storage state = investments[vault][receiver];
        require(state.pendingCancelDepositRequest != true, "InvestmentManager/cancellation-is-pending");

        state.pendingDepositRequest = state.pendingDepositRequest + _assets;
        state.exists = true;

        gateway.send(
            abi.encodePacked(
                uint8(MessagesLib.Call.IncreaseInvestOrder),
                poolId,
                lPool.trancheId(),
                receiver,
                poolManager.currencyAddressToId(asset),
                _assets
            )
        );

        return true;
    }

    /// @notice Request tranche token redemption. Liquidity pools have to request redemptions
    ///         from Centrifuge before actual currency payouts can be done. The redemption
    ///         requests are added to the order book on Centrifuge. Once the next epoch is
    ///         executed on Centrifuge, liquidity pools can proceed with currency payouts
    ///         in case their orders got fulfilled.
    /// @dev    The user tranche tokens required to fulfill the redemption request have to be locked,
    ///         even though the currency payout can only happen after epoch execution.
    function requestRedeem(address vault, uint256 shares, address receiver, address /* owner */ )
        public
        auth
        returns (bool)
    {
        uint128 _shares = shares.toUint128();
        require(_shares != 0, "InvestmentManager/zero-amount-not-allowed");
        VaultLike lPool = VaultLike(vault);

        // You cannot redeem using a disallowed investment currency, instead another LP will have to be used
        require(
            poolManager.isAllowedAsInvestmentCurrency(lPool.poolId(), lPool.asset()),
            "InvestmentManager/currency-not-allowed"
        );

        require(
            _checkTransferRestriction(vault, receiver, address(escrow), convertToAssets(vault, shares)),
            "InvestmentManager/transfer-not-allowed"
        );

        return _processRedeemRequest(vault, _shares, receiver);
    }

    function _processRedeemRequest(address vault, uint128 shares, address owner) internal returns (bool) {
        VaultLike lPool = VaultLike(vault);
        InvestmentState storage state = investments[vault][owner];
        require(state.pendingCancelRedeemRequest != true, "InvestmentManager/cancellation-is-pending");

        state.pendingRedeemRequest = state.pendingRedeemRequest + shares;
        state.exists = true;

        gateway.send(
            abi.encodePacked(
                uint8(MessagesLib.Call.IncreaseRedeemOrder),
                lPool.poolId(),
                lPool.trancheId(),
                owner,
                poolManager.currencyAddressToId(lPool.asset()),
                shares
            )
        );

        return true;
    }

    function cancelDepositRequest(address vault, address owner) public auth {
        VaultLike _vault = VaultLike(vault);

        InvestmentState storage state = investments[vault][owner];
        require(state.pendingCancelDepositRequest != true, "InvestmentManager/cancellation-is-pending");
        state.pendingCancelDepositRequest = true;

        gateway.send(
            abi.encodePacked(
                uint8(MessagesLib.Call.CancelInvestOrder),
                _vault.poolId(),
                _vault.trancheId(),
                owner.toBytes32(),
                poolManager.currencyAddressToId(_vault.asset())
            )
        );
    }

    function cancelRedeemRequest(address vault, address owner) public auth {
        VaultLike _vault = VaultLike(vault);
        uint256 approximateTrancheTokensPayout = pendingRedeemRequest(vault, owner);
        require(
            _checkTransferRestriction(vault, address(0), owner, approximateTrancheTokensPayout),
            "InvestmentManager/transfer-not-allowed"
        );

        InvestmentState storage state = investments[vault][owner];
        require(state.pendingCancelRedeemRequest != true, "InvestmentManager/cancellation-is-pending");
        state.pendingCancelRedeemRequest = true;

        gateway.send(
            abi.encodePacked(
                uint8(MessagesLib.Call.CancelRedeemOrder),
                _vault.poolId(),
                _vault.trancheId(),
                owner.toBytes32(),
                poolManager.currencyAddressToId(_vault.asset())
            )
        );
    }

    // --- Incoming message handling ---
    function handle(bytes calldata message) public auth {
        MessagesLib.Call call = MessagesLib.messageType(message);

        if (call == MessagesLib.Call.ExecutedCollectInvest) {
            handleDepositRequestFulfillment(
                message.toUint64(1),
                message.toBytes16(9),
                message.toAddress(25),
                message.toUint128(57),
                message.toUint128(73),
                message.toUint128(89),
                message.toUint128(105)
            );
        } else if (call == MessagesLib.Call.ExecutedCollectRedeem) {
            handleRedeemRequestFulfillment(
                message.toUint64(1),
                message.toBytes16(9),
                message.toAddress(25),
                message.toUint128(57),
                message.toUint128(73),
                message.toUint128(89)
            );
        } else if (call == MessagesLib.Call.ExecutedDecreaseInvestOrder) {
            handleCancelDepositRequestFulfillment(
                message.toUint64(1),
                message.toBytes16(9),
                message.toAddress(25),
                message.toUint128(57),
                message.toUint128(73),
                message.toUint128(89)
            );
        } else if (call == MessagesLib.Call.ExecutedDecreaseRedeemOrder) {
            handleCancelRedeemRequestFulfillment(
                message.toUint64(1),
                message.toBytes16(9),
                message.toAddress(25),
                message.toUint128(57),
                message.toUint128(73),
                message.toUint128(89)
            );
        } else if (call == MessagesLib.Call.TriggerIncreaseRedeemOrder) {
            handleTriggerRedeemRequest(
                message.toUint64(1),
                message.toBytes16(9),
                message.toAddress(25),
                message.toUint128(57),
                message.toUint128(73)
            );
        } else {
            revert("InvestmentManager/invalid-message");
        }
    }

    function handleDepositRequestFulfillment(
        uint64 poolId,
        bytes16 trancheId,
        address user,
        uint128 assetId,
        uint128 assets,
        uint128 shares,
        uint128 fulfillment
    ) public auth {
        address vault = poolManager.getLiquidityPool(poolId, trancheId, assetId);

        InvestmentState storage state = investments[vault][user];
        state.depositPrice = _calculatePrice(vault, _maxDeposit(vault, user) + assets, state.maxMint + shares);
        state.maxMint = state.maxMint + shares;
        state.pendingDepositRequest =
            state.pendingDepositRequest > fulfillment ? state.pendingDepositRequest - fulfillment : 0;

        if (state.pendingDepositRequest == 0) state.pendingCancelDepositRequest = false;

        // Mint to escrow. Recipient can claim by calling withdraw / redeem
        ERC20Like trancheToken = ERC20Like(VaultLike(vault).share());
        trancheToken.mint(address(escrow), shares);

        VaultLike(vault).emitDepositClaimable(user, assets, shares);
    }

    function handleRedeemRequestFulfillment(
        uint64 poolId,
        bytes16 trancheId,
        address user,
        uint128 assetId,
        uint128 assets,
        uint128 shares
    ) public auth {
        address vault = poolManager.getLiquidityPool(poolId, trancheId, assetId);

        InvestmentState storage state = investments[vault][user];
        require(state.exists == true, "InvestmentManager/non-existent-user");

        // Calculate new weighted average redeem price and update order book values
        state.redeemPrice =
            _calculatePrice(vault, state.maxWithdraw + assets, ((maxRedeem(vault, user)) + shares).toUint128());
        state.maxWithdraw = state.maxWithdraw + assets;
        state.pendingRedeemRequest = state.pendingRedeemRequest > shares ? state.pendingRedeemRequest - shares : 0;

        if (state.pendingRedeemRequest == 0) state.pendingCancelRedeemRequest = false;

        // Burn redeemed tranche tokens from escrow
        ERC20Like trancheToken = ERC20Like(VaultLike(vault).share());
        trancheToken.burn(address(escrow), shares);

        VaultLike(vault).emitRedeemClaimable(user, assets, shares);
    }

    function handleCancelDepositRequestFulfillment(
        uint64 poolId,
        bytes16 trancheId,
        address user,
        uint128 assetId,
        uint128 assets,
        uint128 fulfillment
    ) public auth {
        address vault = poolManager.getLiquidityPool(poolId, trancheId, assetId);

        InvestmentState storage state = investments[vault][user];
        require(state.exists == true, "InvestmentManager/non-existent-user");

        state.claimableCancelDepositRequest = state.claimableCancelDepositRequest + assets;
        state.pendingDepositRequest =
            state.pendingDepositRequest > fulfillment ? state.pendingDepositRequest - fulfillment : 0;

        if (state.pendingDepositRequest == 0) state.pendingCancelDepositRequest = false;

        VaultLike(vault).emitRedeemClaimable(user, assets, assets);
    }

    /// @dev Compared to handleCancelDepositRequestFulfillment, there is no
    ///      transfer of currency in this function because they
    ///      can stay in the Escrow, ready to be claimed on deposit/mint.
    function handleCancelRedeemRequestFulfillment(
        uint64 poolId,
        bytes16 trancheId,
        address user,
        uint128 assetId,
        uint128 shares,
        uint128 fulfillment
    ) public auth {
        address vault = poolManager.getLiquidityPool(poolId, trancheId, assetId);
        InvestmentState storage state = investments[vault][user];

        state.claimableCancelRedeemRequest = state.claimableCancelRedeemRequest + shares;
        state.pendingRedeemRequest =
            state.pendingRedeemRequest > fulfillment ? state.pendingRedeemRequest - fulfillment : 0;

        if (state.pendingRedeemRequest == 0) state.pendingCancelRedeemRequest = false;

        VaultLike(vault).emitRedeemClaimable(user, shares, shares);
    }

    function handleTriggerRedeemRequest(uint64 poolId, bytes16 trancheId, address user, uint128 assetId, uint128 shares)
        public
        auth
    {
        require(shares != 0, "InvestmentManager/tranche-token-amount-is-zero");
        address vault = poolManager.getLiquidityPool(poolId, trancheId, assetId);

        // If there's any unclaimed deposits, claim those first
        InvestmentState storage state = investments[vault][user];
        uint128 tokensToTransfer = shares;
        if (state.maxMint >= shares) {
            // The full redeem request is covered by the claimable amount
            tokensToTransfer = 0;
            state.maxMint = state.maxMint - shares;
        } else if (state.maxMint > 0) {
            // The redeem request is only partially covered by the claimable amount
            tokensToTransfer = shares - state.maxMint;
            state.maxMint = 0;
        }

        require(_processRedeemRequest(vault, shares, user), "InvestmentManager/failed-redeem-request");

        // Transfer the tranche token amount that was not covered by tokens still in escrow for claims,
        // from user to escrow (lock tranche tokens in escrow)
        if (tokensToTransfer > 0) {
            require(
                AuthTransferLike(address(VaultLike(vault).share())).authTransferFrom(
                    user, address(escrow), tokensToTransfer
                ),
                "InvestmentManager/transfer-failed"
            );
        }
        emit TriggerIncreaseRedeemOrder(poolId, trancheId, user, poolManager.assetIdToAddress(assetId), shares);
    }

    // --- View functions ---
    function convertToShares(address vault, uint256 _assets) public view returns (uint256 shares) {
        VaultLike vault_ = VaultLike(vault);
        (uint128 latestPrice,) = poolManager.getTrancheTokenPrice(vault_.poolId(), vault_.trancheId(), vault_.asset());
        shares = uint256(_calculateShares(_assets.toUint128(), vault, latestPrice));
    }

    function convertToAssets(address vault, uint256 _shares) public view returns (uint256 assets) {
        VaultLike vault_ = VaultLike(vault);
        (uint128 latestPrice,) = poolManager.getTrancheTokenPrice(vault_.poolId(), vault_.trancheId(), vault_.asset());
        assets = uint256(_calculateAssets(_shares.toUint128(), vault, latestPrice));
    }

    function maxDeposit(address vault, address user) public view returns (uint256) {
        if (!_checkTransferRestriction(vault, address(escrow), user, 0)) return 0;
        return uint256(_maxDeposit(vault, user));
    }

    function _maxDeposit(address vault, address user) internal view returns (uint128) {
        InvestmentState memory state = investments[vault][user];
        return _calculateAssets(state.maxMint, vault, state.depositPrice);
    }

    function maxMint(address vault, address user) public view returns (uint256 shares) {
        if (!_checkTransferRestriction(vault, address(escrow), user, 0)) return 0;
        return uint256(investments[vault][user].maxMint);
    }

    function maxWithdraw(address vault, address user) public view returns (uint256 assets) {
        return uint256(investments[vault][user].maxWithdraw);
    }

    function maxRedeem(address vault, address user) public view returns (uint256 shares) {
        InvestmentState memory state = investments[vault][user];
        return uint256(_calculateShares(state.maxWithdraw, vault, state.redeemPrice));
    }

    function pendingDepositRequest(address vault, address user) public view returns (uint256 assets) {
        assets = uint256(investments[vault][user].pendingDepositRequest);
    }

    function pendingRedeemRequest(address vault, address user) public view returns (uint256 shares) {
        shares = uint256(investments[vault][user].pendingRedeemRequest);
    }

    function pendingCancelDepositRequest(address vault, address user) public view returns (bool isPending) {
        isPending = investments[vault][user].pendingCancelDepositRequest;
    }

    function pendingCancelRedeemRequest(address vault, address user) public view returns (bool isPending) {
        isPending = investments[vault][user].pendingCancelRedeemRequest;
    }

    function claimableCancelDepositRequest(address vault, address user) public view returns (uint256 assets) {
        assets = investments[vault][user].claimableCancelDepositRequest;
    }

    function claimableCancelRedeemRequest(address vault, address user) public view returns (uint256 shares) {
        shares = investments[vault][user].claimableCancelRedeemRequest;
    }

    function exchangeRateLastUpdated(address vault) public view returns (uint64 lastUpdated) {
        VaultLike vault_ = VaultLike(vault);
        (, lastUpdated) = poolManager.getTrancheTokenPrice(vault_.poolId(), vault_.trancheId(), vault_.asset());
    }

    // --- Liquidity Pool processing functions ---
    /// @notice Processes owner's currency deposit / investment after the epoch has been executed on Centrifuge.
    ///         The currency required to fulfill the invest order is already locked in escrow upon calling
    ///         requestDeposit.
    function deposit(address vault, uint256 assets, address receiver, address owner)
        public
        auth
        returns (uint256 shares)
    {
        InvestmentState storage state = investments[vault][owner];
        uint128 shares_ = _calculateShares(assets.toUint128(), vault, state.depositPrice);
        _processDeposit(state, shares_, vault, receiver);
        shares = uint256(shares_);
    }

    /// @notice Processes owner's currency deposit / investment after the epoch has been executed on Centrifuge.
    ///         The currency required to fulfill the invest order is already locked in escrow upon calling
    ///         requestDeposit.
    function mint(address vault, uint256 shares, address receiver, address owner)
        public
        auth
        returns (uint256 assets)
    {
        InvestmentState storage state = investments[vault][owner];
        _processDeposit(state, shares.toUint128(), vault, receiver);
        assets = uint256(_calculateAssets(shares.toUint128(), vault, state.depositPrice));
    }

    function _processDeposit(InvestmentState storage state, uint128 shares, address vault, address receiver) internal {
        require(shares != 0, "InvestmentManager/tranche-token-amount-is-zero");
        require(shares <= state.maxMint, "InvestmentManager/exceeds-deposit-limits");
        state.maxMint = state.maxMint - shares;
        require(
            ERC20Like(VaultLike(vault).share()).transferFrom(address(escrow), receiver, shares),
            "InvestmentManager/tranche-tokens-transfer-failed"
        );
    }

    /// @dev    Processes owner's tranche Token redemption after the epoch has been executed on Centrifuge.
    ///         The shares required to fulfill the redemption order was already locked in escrow
    ///         upon calling requestRedeem.
    function redeem(address vault, uint256 shares, address receiver, address owner)
        public
        auth
        returns (uint256 assets)
    {
        InvestmentState storage state = investments[vault][owner];
        uint128 assets_ = _calculateAssets(shares.toUint128(), vault, state.redeemPrice);
        _processRedeem(state, assets_, vault, receiver);
        assets = uint256(assets_);
    }

    /// @dev    Processes owner's tranche token redemption after the epoch has been executed on Centrifuge.
    ///         The shares required to fulfill the redemption order was already locked in escrow
    ///         upon calling requestRedeem.
    function withdraw(address vault, uint256 assets, address receiver, address owner)
        public
        auth
        returns (uint256 shares)
    {
        InvestmentState storage state = investments[vault][owner];
        _processRedeem(state, assets.toUint128(), vault, receiver);
        shares = uint256(_calculateShares(assets.toUint128(), vault, state.redeemPrice));
    }

    function _processRedeem(InvestmentState storage state, uint128 assets, address vault, address receiver) internal {
        VaultLike lPool = VaultLike(vault);
        require(assets != 0, "InvestmentManager/currency-amount-is-zero");
        require(assets <= state.maxWithdraw, "InvestmentManager/exceeds-redeem-limits");
        state.maxWithdraw = state.maxWithdraw - assets;
        SafeTransferLib.safeTransferFrom(lPool.asset(), address(escrow), receiver, assets);
    }

    function claimCancelDepositRequest(address vault, address receiver, address owner)
        public
        auth
        returns (uint256 assets)
    {
        InvestmentState storage state = investments[vault][owner];
        assets = state.claimableCancelDepositRequest;
        state.claimableCancelDepositRequest = 0;
        SafeTransferLib.safeTransferFrom(VaultLike(vault).asset(), address(escrow), receiver, assets);
    }

    function claimCancelRedeemRequest(address vault, address receiver, address owner)
        public
        auth
        returns (uint256 shares)
    {
        InvestmentState storage state = investments[vault][owner];
        shares = state.claimableCancelRedeemRequest;
        state.claimableCancelRedeemRequest = 0;
        require(
            ERC20Like(VaultLike(vault).share()).transferFrom(address(escrow), receiver, shares),
            "InvestmentManager/tranche-tokens-transfer-failed"
        );
    }

    // --- Helpers ---
    function _calculateShares(uint128 assets, address vault, uint256 price) internal view returns (uint128 shares) {
        if (price == 0 || assets == 0) {
            shares = 0;
        } else {
            (uint8 assetDecimals, uint8 shareDecimals) = _getPoolDecimals(vault);

            uint256 sharesInPriceDecimals =
                _toPriceDecimals(assets, assetDecimals).mulDiv(10 ** PRICE_DECIMALS, price, MathLib.Rounding.Down);

            shares = _fromPriceDecimals(sharesInPriceDecimals, shareDecimals);
        }
    }

    function _calculateAssets(uint128 shares, address vault, uint256 price) internal view returns (uint128 assets) {
        if (price == 0 || shares == 0) {
            assets = 0;
        } else {
            (uint8 assetDecimals, uint8 shareDecimals) = _getPoolDecimals(vault);

            uint256 assetsInPriceDecimals =
                _toPriceDecimals(shares, shareDecimals).mulDiv(price, 10 ** PRICE_DECIMALS, MathLib.Rounding.Down);

            assets = _fromPriceDecimals(assetsInPriceDecimals, assetDecimals);
        }
    }

    function _calculatePrice(address vault, uint128 assets, uint128 shares) internal view returns (uint256 price) {
        (uint8 assetDecimals, uint8 shareDecimals) = _getPoolDecimals(vault);
        price = _calculatePrice(_toPriceDecimals(assets, assetDecimals), _toPriceDecimals(shares, shareDecimals));
    }

    function _calculatePrice(uint256 assetsInPriceDecimals, uint256 sharesInPriceDecimals)
        internal
        pure
        returns (uint256 price)
    {
        if (assetsInPriceDecimals == 0 || sharesInPriceDecimals == 0) {
            return 0;
        }

        price = assetsInPriceDecimals.mulDiv(10 ** PRICE_DECIMALS, sharesInPriceDecimals, MathLib.Rounding.Down);
    }

    /// @dev    When converting currency to tranche token amounts using the price,
    ///         all values are normalized to PRICE_DECIMALS
    function _toPriceDecimals(uint128 _value, uint8 decimals) internal pure returns (uint256 value) {
        if (PRICE_DECIMALS == decimals) return uint256(_value);
        value = uint256(_value) * 10 ** (PRICE_DECIMALS - decimals);
    }

    /// @dev    Convert decimals of the value from the price decimals back to the intended decimals
    function _fromPriceDecimals(uint256 _value, uint8 decimals) internal pure returns (uint128 value) {
        if (PRICE_DECIMALS == decimals) return _value.toUint128();
        value = (_value / 10 ** (PRICE_DECIMALS - decimals)).toUint128();
    }

    /// @dev    Return the currency decimals and the tranche token decimals for a given vault
    function _getPoolDecimals(address vault) internal view returns (uint8 assetDecimals, uint8 shareDecimals) {
        assetDecimals = ERC20Like(VaultLike(vault).asset()).decimals();
        shareDecimals = ERC20Like(VaultLike(vault).share()).decimals();
    }

    function _checkTransferRestriction(address vault, address from, address to, uint256 value)
        internal
        view
        returns (bool)
    {
        TrancheTokenLike trancheToken = TrancheTokenLike(VaultLike(vault).share());
        return trancheToken.checkTransferRestriction(from, to, value);
    }
}
