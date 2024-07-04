// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.26;

import {Auth} from "src/Auth.sol";
import {CastLib} from "src/libraries/CastLib.sol";
import {MathLib} from "src/libraries/MathLib.sol";
import {SafeTransferLib} from "src/libraries/SafeTransferLib.sol";
import {MessagesLib} from "src/libraries/MessagesLib.sol";
import {BytesLib} from "src/libraries/BytesLib.sol";
import {IRoot} from "src/interfaces/IRoot.sol";
import {IERC20, IERC20Metadata} from "src/interfaces/IERC20.sol";
import {IPoolManager} from "src/interfaces/IPoolManager.sol";
import {IInvestmentManager, Vault, InvestmentState} from "src/interfaces/IInvestmentManager.sol";
import {ITranche} from "src/interfaces/token/ITranche.sol";
import {IERC7540Vault} from "src/interfaces/IERC7540.sol";
import {IGateway} from "src/interfaces/gateway/IGateway.sol";

/// @title  Investment Manager
/// @notice This is the main contract vaults interact with for
///         both incoming and outgoing investment transactions.
contract InvestmentManager is Auth, IInvestmentManager {
    using BytesLib for bytes;
    using MathLib for uint256;
    using CastLib for *;

    /// @dev Prices are fixed-point integers with 18 decimals
    uint8 internal constant PRICE_DECIMALS = 18;

    address public immutable root;
    address public immutable escrow;

    IGateway public gateway;
    IPoolManager public poolManager;

    mapping(address vault => mapping(address investor => InvestmentState)) public investments;

    constructor(address root_, address escrow_) {
        root = root_;
        escrow = escrow_;

        wards[msg.sender] = 1;
        emit Rely(msg.sender);
    }

    // --- Administration ---
    /// @inheritdoc IInvestmentManager
    function file(bytes32 what, address data) external auth {
        if (what == "gateway") gateway = IGateway(data);
        else if (what == "poolManager") poolManager = IPoolManager(data);
        else revert("InvestmentManager/file-unrecognized-param");
        emit File(what, data);
    }

    /// @inheritdoc IInvestmentManager
    function recoverTokens(address token, address to, uint256 amount) external auth {
        SafeTransferLib.safeTransfer(token, to, amount);
    }

    // --- Outgoing message handling ---
    /// @inheritdoc IInvestmentManager
    function requestDeposit(Vault calldata vault, uint256 assets, address receiver, address owner, address source)
        public
        auth
        returns (bool)
    {
        uint128 _assets = assets.toUint128();
        require(_assets != 0, "InvestmentManager/zero-amount-not-allowed");
        require(poolManager.isAllowedAsset(vault.poolId, vault.asset), "InvestmentManager/asset-not-allowed");

        require(_canTransfer(vault, address(0), owner, 0), "InvestmentManager/owner-is-restricted");
        require(
            _canTransfer(vault, address(0), receiver, convertToShares(vault, assets)),
            "InvestmentManager/transfer-not-allowed"
        );

        InvestmentState storage state = investments[vault.addr][receiver];
        require(state.pendingCancelDepositRequest != true, "InvestmentManager/cancellation-is-pending");

        state.pendingDepositRequest = state.pendingDepositRequest + _assets;
        gateway.send(
            abi.encodePacked(
                uint8(MessagesLib.Call.IncreaseInvestOrder),
                vault.poolId,
                vault.trancheId,
                receiver.toBytes32(),
                poolManager.assetToId(vault.asset),
                _assets
            ),
            source
        );

        return true;
    }

    /// @inheritdoc IInvestmentManager
    function requestRedeem(Vault calldata vault, uint256 shares, address receiver, /* owner */ address, address source)
        public
        auth
        returns (bool)
    {
        uint128 _shares = shares.toUint128();
        require(_shares != 0, "InvestmentManager/zero-amount-not-allowed");

        // You cannot redeem using a disallowed asset, instead another vault will have to be used
        require(poolManager.isAllowedAsset(vault.poolId, vault.asset), "InvestmentManager/asset-not-allowed");

        require(
            _canTransfer(vault, receiver, address(escrow), convertToAssets(vault, shares)),
            "InvestmentManager/transfer-not-allowed"
        );
        return _processRedeemRequest(vault, _shares, receiver, source);
    }

    function _processRedeemRequest(Vault memory vault, uint128 shares, address owner, address source)
        internal
        returns (bool)
    {
        InvestmentState storage state = investments[vault.addr][owner];
        require(state.pendingCancelRedeemRequest != true, "InvestmentManager/cancellation-is-pending");

        state.pendingRedeemRequest = state.pendingRedeemRequest + shares;

        gateway.send(
            abi.encodePacked(
                uint8(MessagesLib.Call.IncreaseRedeemOrder),
                vault.poolId,
                vault.trancheId,
                owner.toBytes32(),
                poolManager.assetToId(vault.asset),
                shares
            ),
            source
        );

        return true;
    }

    /// @inheritdoc IInvestmentManager
    function cancelDepositRequest(Vault calldata vault, address owner, address source) public auth {
        InvestmentState storage state = investments[vault.addr][owner];
        require(state.pendingCancelDepositRequest != true, "InvestmentManager/cancellation-is-pending");
        state.pendingCancelDepositRequest = true;

        gateway.send(
            abi.encodePacked(
                uint8(MessagesLib.Call.CancelInvestOrder),
                vault.poolId,
                vault.trancheId,
                owner.toBytes32(),
                poolManager.assetToId(vault.asset)
            ),
            source
        );
    }

    /// @inheritdoc IInvestmentManager
    function cancelRedeemRequest(Vault calldata vault, address owner, address source) public auth {
        uint256 approximateTranchesPayout = pendingRedeemRequest(vault.addr, owner);
        require(
            _canTransfer(vault, address(0), owner, approximateTranchesPayout), "InvestmentManager/transfer-not-allowed"
        );

        InvestmentState storage state = investments[vault.addr][owner];
        require(state.pendingCancelRedeemRequest != true, "InvestmentManager/cancellation-is-pending");
        state.pendingCancelRedeemRequest = true;

        gateway.send(
            abi.encodePacked(
                uint8(MessagesLib.Call.CancelRedeemOrder),
                vault.poolId,
                vault.trancheId,
                owner.toBytes32(),
                poolManager.assetToId(vault.asset)
            ),
            source
        );
    }

    // --- Incoming message handling ---
    /// @inheritdoc IInvestmentManager
    function handle(bytes calldata message) public auth {
        MessagesLib.Call call = MessagesLib.messageType(message);

        if (call == MessagesLib.Call.FulfilledDepositRequest) {
            fulfillDepositRequest(
                message.toUint64(1),
                message.toBytes16(9),
                message.toAddress(25),
                message.toUint128(57),
                message.toUint128(73),
                message.toUint128(89),
                message.toUint128(105)
            );
        } else if (call == MessagesLib.Call.FulfilledRedeemRequest) {
            fulfillRedeemRequest(
                message.toUint64(1),
                message.toBytes16(9),
                message.toAddress(25),
                message.toUint128(57),
                message.toUint128(73),
                message.toUint128(89)
            );
        } else if (call == MessagesLib.Call.FulfilledCancelDepositRequest) {
            fulfillCancelDepositRequest(
                message.toUint64(1),
                message.toBytes16(9),
                message.toAddress(25),
                message.toUint128(57),
                message.toUint128(73),
                message.toUint128(89)
            );
        } else if (call == MessagesLib.Call.FulfilledCancelRedeemRequest) {
            fulfillCancelRedeemRequest(
                message.toUint64(1),
                message.toBytes16(9),
                message.toAddress(25),
                message.toUint128(57),
                message.toUint128(73),
                message.toUint128(89)
            );
        } else if (call == MessagesLib.Call.TriggerRedeemRequest) {
            triggerRedeemRequest(
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

    /// @inheritdoc IInvestmentManager
    function fulfillDepositRequest(
        uint64 poolId,
        bytes16 trancheId,
        address user,
        uint128 assetId,
        uint128 assets,
        uint128 shares,
        uint128 fulfillment
    ) public auth {
        Vault memory vault = _vaultData(poolManager.getVault(poolId, trancheId, assetId));

        InvestmentState storage state = investments[vault.addr][user];
        require(state.pendingDepositRequest > 0, "InvestmentManager/no-pending-deposit-request");
        state.depositPrice = _calculatePrice(vault, _maxDeposit(vault, user) + assets, state.maxMint + shares);
        state.maxMint = state.maxMint + shares;
        state.pendingDepositRequest =
            state.pendingDepositRequest > fulfillment ? state.pendingDepositRequest - fulfillment : 0;

        if (state.pendingDepositRequest == 0) state.pendingCancelDepositRequest = false;

        // Mint to escrow. Recipient can claim by calling withdraw / redeem
        ITranche tranche = ITranche(vault.share);
        tranche.mint(address(escrow), shares);

        IERC7540Vault(vault.addr).onDepositClaimable(user, assets, shares);
    }

    /// @inheritdoc IInvestmentManager
    function fulfillRedeemRequest(
        uint64 poolId,
        bytes16 trancheId,
        address user,
        uint128 assetId,
        uint128 assets,
        uint128 shares
    ) public auth {
        Vault memory vault = _vaultData(poolManager.getVault(poolId, trancheId, assetId));

        InvestmentState storage state = investments[vault.addr][user];
        require(state.pendingRedeemRequest > 0, "InvestmentManager/no-pending-redeem-request");

        // Calculate new weighted average redeem price and update order book values
        state.redeemPrice =
            _calculatePrice(vault, state.maxWithdraw + assets, ((maxRedeem(vault, user)) + shares).toUint128());
        state.maxWithdraw = state.maxWithdraw + assets;
        state.pendingRedeemRequest = state.pendingRedeemRequest > shares ? state.pendingRedeemRequest - shares : 0;

        if (state.pendingRedeemRequest == 0) state.pendingCancelRedeemRequest = false;

        // Burn redeemed tranche tokens from escrow
        ITranche tranche = ITranche(vault.share);
        tranche.burn(address(escrow), shares);

        IERC7540Vault(vault.addr).onRedeemClaimable(user, assets, shares);
    }

    /// @inheritdoc IInvestmentManager
    function fulfillCancelDepositRequest(
        uint64 poolId,
        bytes16 trancheId,
        address user,
        uint128 assetId,
        uint128 assets,
        uint128 fulfillment
    ) public auth {
        address vault = poolManager.getVault(poolId, trancheId, assetId);

        InvestmentState storage state = investments[vault][user];
        require(state.pendingCancelDepositRequest == true, "InvestmentManager/no-pending-cancel-deposit-request");

        state.claimableCancelDepositRequest = state.claimableCancelDepositRequest + assets;
        state.pendingDepositRequest =
            state.pendingDepositRequest > fulfillment ? state.pendingDepositRequest - fulfillment : 0;

        if (state.pendingDepositRequest == 0) state.pendingCancelDepositRequest = false;

        IERC7540Vault(vault).onCancelDepositClaimable(user, assets);
    }

    /// @inheritdoc IInvestmentManager
    function fulfillCancelRedeemRequest(
        uint64 poolId,
        bytes16 trancheId,
        address user,
        uint128 assetId,
        uint128 shares,
        uint128 fulfillment
    ) public auth {
        address vault = poolManager.getVault(poolId, trancheId, assetId);
        InvestmentState storage state = investments[vault][user];
        require(state.pendingCancelRedeemRequest == true, "InvestmentManager/no-pending-cancel-redeem-request");

        state.claimableCancelRedeemRequest = state.claimableCancelRedeemRequest + shares;
        state.pendingRedeemRequest =
            state.pendingRedeemRequest > fulfillment ? state.pendingRedeemRequest - fulfillment : 0;

        if (state.pendingRedeemRequest == 0) state.pendingCancelRedeemRequest = false;

        IERC7540Vault(vault).onCancelRedeemClaimable(user, shares);
    }

    /// @inheritdoc IInvestmentManager
    function triggerRedeemRequest(uint64 poolId, bytes16 trancheId, address user, uint128 assetId, uint128 shares)
        public
        auth
    {
        require(shares != 0, "InvestmentManager/tranche-token-amount-is-zero");
        Vault memory vault = _vaultData(poolManager.getVault(poolId, trancheId, assetId));

        // If there's any unclaimed deposits, claim those first
        InvestmentState storage state = investments[vault.addr][user];
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

        require(_processRedeemRequest(vault, shares, user, msg.sender), "InvestmentManager/failed-redeem-request");

        // Transfer the tranche token amount that was not covered by tokens still in escrow for claims,
        // from user to escrow (lock tranche tokens in escrow)
        if (tokensToTransfer > 0) {
            require(
                ITranche(vault.share).authTransferFrom(user, user, address(escrow), tokensToTransfer),
                "InvestmentManager/transfer-failed"
            );
        }
        emit TriggerRedeemRequest(poolId, trancheId, user, poolManager.idToAsset(assetId), shares);
    }

    // --- View functions ---
    /// @inheritdoc IInvestmentManager
    function convertToShares(Vault calldata vault, uint256 _assets) public view returns (uint256 shares) {
        (uint128 latestPrice,) = poolManager.getTranchePrice(vault.poolId, vault.trancheId, vault.asset);
        shares = uint256(_calculateShares(_assets.toUint128(), vault, latestPrice));
    }

    /// @inheritdoc IInvestmentManager
    function convertToAssets(Vault calldata vault, uint256 _shares) public view returns (uint256 assets) {
        (uint128 latestPrice,) = poolManager.getTranchePrice(vault.poolId, vault.trancheId, vault.asset);
        assets = uint256(_calculateAssets(_shares.toUint128(), vault, latestPrice));
    }

    /// @inheritdoc IInvestmentManager
    function maxDeposit(Vault calldata vault, address user) public view returns (uint256) {
        if (!_canTransfer(vault, address(escrow), user, 0)) return 0;
        return uint256(_maxDeposit(vault, user));
    }

    function _maxDeposit(Vault memory vault, address user) internal view returns (uint128) {
        InvestmentState memory state = investments[vault.addr][user];
        return _calculateAssets(state.maxMint, vault, state.depositPrice);
    }

    /// @inheritdoc IInvestmentManager
    function maxMint(Vault calldata vault, address user) public view returns (uint256 shares) {
        if (!_canTransfer(vault, address(escrow), user, 0)) return 0;
        return uint256(investments[vault.addr][user].maxMint);
    }

    /// @inheritdoc IInvestmentManager
    function maxWithdraw(Vault calldata vault, address user) public view returns (uint256 assets) {
        return uint256(investments[vault.addr][user].maxWithdraw);
    }

    /// @inheritdoc IInvestmentManager
    function maxRedeem(Vault memory vault, address user) public view returns (uint256 shares) {
        InvestmentState memory state = investments[vault.addr][user];
        return uint256(_calculateShares(state.maxWithdraw, vault, state.redeemPrice));
    }

    /// @inheritdoc IInvestmentManager
    function pendingDepositRequest(address vault, address user) public view returns (uint256 assets) {
        assets = uint256(investments[vault][user].pendingDepositRequest);
    }

    /// @inheritdoc IInvestmentManager
    function pendingRedeemRequest(address vault, address user) public view returns (uint256 shares) {
        shares = uint256(investments[vault][user].pendingRedeemRequest);
    }

    /// @inheritdoc IInvestmentManager
    function pendingCancelDepositRequest(address vault, address user) public view returns (bool isPending) {
        isPending = investments[vault][user].pendingCancelDepositRequest;
    }

    /// @inheritdoc IInvestmentManager
    function pendingCancelRedeemRequest(address vault, address user) public view returns (bool isPending) {
        isPending = investments[vault][user].pendingCancelRedeemRequest;
    }

    /// @inheritdoc IInvestmentManager
    function claimableCancelDepositRequest(address vault, address user) public view returns (uint256 assets) {
        assets = investments[vault][user].claimableCancelDepositRequest;
    }

    /// @inheritdoc IInvestmentManager
    function claimableCancelRedeemRequest(address vault, address user) public view returns (uint256 shares) {
        shares = investments[vault][user].claimableCancelRedeemRequest;
    }

    /// @inheritdoc IInvestmentManager
    function priceLastUpdated(address vault) public view returns (uint64 lastUpdated) {
        IERC7540Vault vault_ = IERC7540Vault(vault);
        (, lastUpdated) = poolManager.getTranchePrice(vault_.poolId(), vault_.trancheId(), vault_.asset());
    }

    /// @inheritdoc IInvestmentManager
    function isGlobalOperator(address, /* vault */ address user) public view returns (bool) {
        return IRoot(root).endorsed(user);
    }

    // --- Vault claim functions ---
    /// @inheritdoc IInvestmentManager
    function deposit(Vault calldata vault, uint256 assets, address receiver, address owner)
        public
        auth
        returns (uint256 shares)
    {
        InvestmentState storage state = investments[vault.addr][owner];
        uint128 shares_ = _calculateShares(assets.toUint128(), vault, state.depositPrice);
        _processDeposit(state, shares_, vault, receiver);
        shares = uint256(shares_);
    }

    /// @inheritdoc IInvestmentManager
    function mint(Vault calldata vault, uint256 shares, address receiver, address owner)
        public
        auth
        returns (uint256 assets)
    {
        InvestmentState storage state = investments[vault.addr][owner];
        _processDeposit(state, shares.toUint128(), vault, receiver);
        assets = uint256(_calculateAssets(shares.toUint128(), vault, state.depositPrice));
    }

    function _processDeposit(InvestmentState storage state, uint128 shares, Vault memory vault, address receiver)
        internal
    {
        require(shares != 0, "InvestmentManager/tranche-token-amount-is-zero");
        require(shares <= state.maxMint, "InvestmentManager/exceeds-deposit-limits");
        state.maxMint = state.maxMint - shares;
        require(
            IERC20(vault.share).transferFrom(address(escrow), receiver, shares),
            "InvestmentManager/tranche-tokens-transfer-failed"
        );
    }

    /// @inheritdoc IInvestmentManager
    function redeem(Vault calldata vault, uint256 shares, address receiver, address owner)
        public
        auth
        returns (uint256 assets)
    {
        InvestmentState storage state = investments[vault.addr][owner];
        uint128 assets_ = _calculateAssets(shares.toUint128(), vault, state.redeemPrice);
        _processRedeem(state, assets_, vault, receiver);
        assets = uint256(assets_);
    }

    /// @inheritdoc IInvestmentManager
    function withdraw(Vault calldata vault, uint256 assets, address receiver, address owner)
        public
        auth
        returns (uint256 shares)
    {
        InvestmentState storage state = investments[vault.addr][owner];
        _processRedeem(state, assets.toUint128(), vault, receiver);
        shares = uint256(_calculateShares(assets.toUint128(), vault, state.redeemPrice));
    }

    function _processRedeem(InvestmentState storage state, uint128 assets, Vault memory vault, address receiver)
        internal
    {
        require(assets != 0, "InvestmentManager/asset-amount-is-zero");
        require(assets <= state.maxWithdraw, "InvestmentManager/exceeds-redeem-limits");
        state.maxWithdraw = state.maxWithdraw - assets;
        SafeTransferLib.safeTransferFrom(vault.asset, address(escrow), receiver, assets);
    }

    /// @inheritdoc IInvestmentManager
    function claimCancelDepositRequest(Vault calldata vault, address receiver, address owner)
        public
        auth
        returns (uint256 assets)
    {
        InvestmentState storage state = investments[vault.addr][owner];
        assets = state.claimableCancelDepositRequest;
        state.claimableCancelDepositRequest = 0;
        SafeTransferLib.safeTransferFrom(vault.asset, address(escrow), receiver, assets);
    }

    /// @inheritdoc IInvestmentManager
    function claimCancelRedeemRequest(Vault calldata vault, address receiver, address owner)
        public
        auth
        returns (uint256 shares)
    {
        InvestmentState storage state = investments[vault.addr][owner];
        shares = state.claimableCancelRedeemRequest;
        state.claimableCancelRedeemRequest = 0;
        require(
            IERC20(vault.share).transferFrom(address(escrow), receiver, shares),
            "InvestmentManager/tranche-tokens-transfer-failed"
        );
    }

    // --- Helpers ---
    function _calculateShares(uint128 assets, Vault memory vault, uint256 price)
        internal
        view
        returns (uint128 shares)
    {
        if (price == 0 || assets == 0) {
            shares = 0;
        } else {
            uint256 sharesInPriceDecimals =
                _toPriceDecimals(assets, vault.assetDecimals).mulDiv(10 ** PRICE_DECIMALS, price, MathLib.Rounding.Down);

            shares = _fromPriceDecimals(sharesInPriceDecimals, vault.shareDecimals);
        }
    }

    function _calculateAssets(uint128 shares, Vault memory vault, uint256 price)
        internal
        view
        returns (uint128 assets)
    {
        if (price == 0 || shares == 0) {
            assets = 0;
        } else {
            uint256 assetsInPriceDecimals =
                _toPriceDecimals(shares, vault.shareDecimals).mulDiv(price, 10 ** PRICE_DECIMALS, MathLib.Rounding.Down);

            assets = _fromPriceDecimals(assetsInPriceDecimals, vault.assetDecimals);
        }
    }

    function _calculatePrice(Vault memory vault, uint128 assets, uint128 shares)
        internal
        pure
        returns (uint256 price)
    {
        if (assets == 0 || shares == 0) {
            return 0;
        }

        price = _toPriceDecimals(assets, vault.assetDecimals).mulDiv(
            10 ** PRICE_DECIMALS, _toPriceDecimals(shares, vault.shareDecimals), MathLib.Rounding.Down
        );
    }

    /// @dev    When converting assets to shares using the price,
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

    function _canTransfer(Vault calldata vault, address from, address to, uint256 value) internal view returns (bool) {
        ITranche share = ITranche(vault.share);
        return share.checkTransferRestriction(from, to, value);
    }

    function _vaultData(address vault_) internal view returns (Vault memory) {
        IERC7540Vault vault = IERC7540Vault(vault_);
        return Vault(
            vault_,
            vault.asset(),
            vault.share(),
            vault.shareDecimals(),
            vault.assetDecimals(),
            vault.poolId(),
            vault.trancheId()
        );
    }
}
