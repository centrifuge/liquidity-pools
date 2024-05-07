// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import {Auth} from "src/Auth.sol";
import {CastLib} from "src/libraries/CastLib.sol";
import {MathLib} from "src/libraries/MathLib.sol";
import {SafeTransferLib} from "src/libraries/SafeTransferLib.sol";
import {MessagesLib} from "src/libraries/MessagesLib.sol";
import {BytesLib} from "src/libraries/BytesLib.sol";
import {IERC20, IERC20Metadata} from "src/interfaces/IERC20.sol";
import {IPoolManager} from "src/interfaces/IPoolManager.sol";
import {IInvestmentManager, Request} from "src/interfaces/IInvestmentManager.sol";

interface GatewayLike {
    function send(bytes memory message) external;
}

interface TrancheTokenLike is IERC20 {
    function checkTransferRestriction(address from, address to, uint256 value) external view returns (bool);
    function mint(address user, uint256 value) external;
    function burn(address user, uint256 value) external;
}

interface VaultLike is IERC20 {
    function poolId() external view returns (uint64);
    function trancheId() external view returns (bytes16);
    function asset() external view returns (address);
    function share() external view returns (address);
    function emitDepositClaimable(address owner, uint256 assets, uint256 shares) external;
    function emitRedeemClaimable(address owner, uint256 assets, uint256 shares) external;
    function emitCancelDepositClaimable(address owner, uint256 assets) external;
    function emitCancelRedeemClaimable(address owner, uint256 shares) external;
}

interface AuthTransferLike {
    function authTransferFrom(address sender, address from, address to, uint256 amount) external returns (bool);
}

/// @title  Investment Manager
/// @notice This is the main contract vaults interact with for
///         both incoming and outgoing investment transactions.
contract InvestmentManager is Auth, IInvestmentManager {
    using BytesLib for bytes;
    using MathLib for uint256;
    using CastLib for *;

    /// @dev Prices are fixed-point integers with 18 decimals
    uint8 internal constant PRICE_DECIMALS = 18;

    address public immutable escrow;

    GatewayLike public gateway;
    IPoolManager public poolManager;

    mapping(address vault => mapping(address investor => Request)) public requests;

    constructor(address escrow_) {
        escrow = escrow_;

        wards[msg.sender] = 1;
        emit Rely(msg.sender);
    }

    // --- Administration ---
    /// @inheritdoc IInvestmentManager
    function file(bytes32 what, address data) external auth {
        if (what == "gateway") gateway = GatewayLike(data);
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
    function requestDeposit(address vault, uint256 assets, address receiver, address owner)
        public
        auth
        returns (bool)
    {
        VaultLike vault_ = VaultLike(vault);
        uint128 _assets = assets.toUint128();
        require(_assets != 0, "InvestmentManager/zero-amount-not-allowed");

        uint64 poolId = vault_.poolId();
        address asset = vault_.asset();
        require(poolManager.isAllowedAsset(poolId, asset), "InvestmentManager/asset-not-allowed");

        require(_canTransfer(vault, address(0), owner, 0), "InvestmentManager/owner-is-restricted");
        require(
            _canTransfer(vault, address(0), receiver, convertToShares(vault, assets)),
            "InvestmentManager/transfer-not-allowed"
        );

        Request storage request = requests[vault][receiver];
        require(request.pendingCancelDeposit != true, "InvestmentManager/cancellation-is-pending");

        request.pendingDeposit = request.pendingDeposit + _assets;
        request.exists = true;

        gateway.send(
            abi.encodePacked(
                uint8(MessagesLib.Call.IncreaseInvestOrder),
                poolId,
                vault_.trancheId(),
                receiver,
                poolManager.assetToId(asset),
                _assets
            )
        );

        return true;
    }

    /// @inheritdoc IInvestmentManager
    function requestRedeem(address vault, uint256 shares, address receiver, address /* owner */ )
        public
        auth
        returns (bool)
    {
        uint128 _shares = shares.toUint128();
        require(_shares != 0, "InvestmentManager/zero-amount-not-allowed");
        VaultLike vault_ = VaultLike(vault);

        // You cannot redeem using a disallowed asset, instead another vault will have to be used
        require(poolManager.isAllowedAsset(vault_.poolId(), vault_.asset()), "InvestmentManager/asset-not-allowed");

        require(
            _canTransfer(vault, receiver, address(escrow), convertToAssets(vault, shares)),
            "InvestmentManager/transfer-not-allowed"
        );

        return _processRedeemRequest(vault, _shares, receiver);
    }

    function _processRedeemRequest(address vault, uint128 shares, address owner) internal returns (bool) {
        VaultLike vault_ = VaultLike(vault);
        Request storage request = requests[vault][owner];
        require(request.pendingCancelRedeem != true, "InvestmentManager/cancellation-is-pending");

        request.pendingRedeem = request.pendingRedeem + shares;
        request.exists = true;

        gateway.send(
            abi.encodePacked(
                uint8(MessagesLib.Call.IncreaseRedeemOrder),
                vault_.poolId(),
                vault_.trancheId(),
                owner,
                poolManager.assetToId(vault_.asset()),
                shares
            )
        );

        return true;
    }

    /// @inheritdoc IInvestmentManager
    function cancelDepositRequest(address vault, address owner) public auth {
        VaultLike _vault = VaultLike(vault);

        Request storage request = requests[vault][owner];
        require(request.pendingCancelDeposit != true, "InvestmentManager/cancellation-is-pending");
        request.pendingCancelDeposit = true;

        gateway.send(
            abi.encodePacked(
                uint8(MessagesLib.Call.CancelInvestOrder),
                _vault.poolId(),
                _vault.trancheId(),
                owner.toBytes32(),
                poolManager.assetToId(_vault.asset())
            )
        );
    }

    /// @inheritdoc IInvestmentManager
    function cancelRedeemRequest(address vault, address owner) public auth {
        VaultLike _vault = VaultLike(vault);
        require(
            _canTransfer(vault, address(0), owner, pendingRedeemRequest(vault, owner)),
            "InvestmentManager/transfer-not-allowed"
        );

        Request storage request = requests[vault][owner];
        require(request.pendingCancelRedeem != true, "InvestmentManager/cancellation-is-pending");
        request.pendingCancelRedeem = true;

        gateway.send(
            abi.encodePacked(
                uint8(MessagesLib.Call.CancelRedeemOrder),
                _vault.poolId(),
                _vault.trancheId(),
                owner.toBytes32(),
                poolManager.assetToId(_vault.asset())
            )
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
        address vault = poolManager.getVault(poolId, trancheId, assetId);

        Request storage request = requests[vault][user];
        request.depositPrice = _calculatePrice(vault, _maxDeposit(vault, user) + assets, request.maxMint + shares);
        request.maxMint = request.maxMint + shares;
        request.pendingDeposit = request.pendingDeposit > fulfillment ? request.pendingDeposit - fulfillment : 0;

        if (request.pendingDeposit == 0) request.pendingCancelDeposit = false;

        // Mint to escrow. Recipient can claim by calling withdraw / redeem
        TrancheTokenLike trancheToken = TrancheTokenLike(VaultLike(vault).share());
        trancheToken.mint(address(escrow), shares);

        VaultLike(vault).emitDepositClaimable(user, assets, shares);
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
        address vault = poolManager.getVault(poolId, trancheId, assetId);

        Request storage request = requests[vault][user];
        require(request.exists == true, "InvestmentManager/non-existent-user");

        // Calculate new weighted average redeem price and update order book values
        request.redeemPrice =
            _calculatePrice(vault, request.maxWithdraw + assets, ((maxRedeem(vault, user)) + shares).toUint128());
        request.maxWithdraw = request.maxWithdraw + assets;
        request.pendingRedeem = request.pendingRedeem > shares ? request.pendingRedeem - shares : 0;

        if (request.pendingRedeem == 0) request.pendingCancelRedeem = false;

        // Burn redeemed tranche tokens from escrow
        TrancheTokenLike trancheToken = TrancheTokenLike(VaultLike(vault).share());
        trancheToken.burn(address(escrow), shares);

        VaultLike(vault).emitRedeemClaimable(user, assets, shares);
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

        Request storage request = requests[vault][user];
        require(request.exists == true, "InvestmentManager/non-existent-user");

        request.claimableCancelDeposit = request.claimableCancelDeposit + assets;
        request.pendingDeposit = request.pendingDeposit > fulfillment ? request.pendingDeposit - fulfillment : 0;

        if (request.pendingDeposit == 0) request.pendingCancelDeposit = false;

        VaultLike(vault).emitCancelDepositClaimable(user, assets);
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
        Request storage request = requests[vault][user];

        request.claimableCancelRedeem = request.claimableCancelRedeem + shares;
        request.pendingRedeem = request.pendingRedeem > fulfillment ? request.pendingRedeem - fulfillment : 0;

        if (request.pendingRedeem == 0) request.pendingCancelRedeem = false;

        VaultLike(vault).emitCancelRedeemClaimable(user, shares);
    }

    /// @inheritdoc IInvestmentManager
    function triggerRedeemRequest(uint64 poolId, bytes16 trancheId, address user, uint128 assetId, uint128 shares)
        public
        auth
    {
        require(shares != 0, "InvestmentManager/tranche-token-amount-is-zero");
        address vault = poolManager.getVault(poolId, trancheId, assetId);

        // If there's any unclaimed deposits, claim those first
        Request storage request = requests[vault][user];
        uint128 tokensToTransfer = shares;
        if (request.maxMint >= shares) {
            // The full redeem request is covered by the claimable amount
            tokensToTransfer = 0;
            request.maxMint = request.maxMint - shares;
        } else if (request.maxMint > 0) {
            // The redeem request is only partially covered by the claimable amount
            tokensToTransfer = shares - request.maxMint;
            request.maxMint = 0;
        }

        require(_processRedeemRequest(vault, shares, user), "InvestmentManager/failed-redeem-request");

        // Transfer the tranche token amount that was not covered by tokens still in escrow for claims,
        // from user to escrow (lock tranche tokens in escrow)
        if (tokensToTransfer > 0) {
            require(
                AuthTransferLike(address(VaultLike(vault).share())).authTransferFrom(
                    user, user, address(escrow), tokensToTransfer
                ),
                "InvestmentManager/transfer-failed"
            );
        }
        emit TriggerRedeemRequest(poolId, trancheId, user, poolManager.idToAsset(assetId), shares);
    }

    // --- View functions ---
    /// @inheritdoc IInvestmentManager
    function convertToShares(address vault, uint256 _assets) public view returns (uint256 shares) {
        VaultLike vault_ = VaultLike(vault);
        (uint128 latestPrice,) = poolManager.getTrancheTokenPrice(vault_.poolId(), vault_.trancheId(), vault_.asset());
        shares = uint256(_calculateShares(_assets.toUint128(), vault, latestPrice));
    }

    /// @inheritdoc IInvestmentManager
    function convertToAssets(address vault, uint256 _shares) public view returns (uint256 assets) {
        VaultLike vault_ = VaultLike(vault);
        (uint128 latestPrice,) = poolManager.getTrancheTokenPrice(vault_.poolId(), vault_.trancheId(), vault_.asset());
        assets = uint256(_calculateAssets(_shares.toUint128(), vault, latestPrice));
    }

    /// @inheritdoc IInvestmentManager
    function maxDeposit(address vault, address user) public view returns (uint256) {
        if (!_canTransfer(vault, address(escrow), user, 0)) return 0;
        return uint256(_maxDeposit(vault, user));
    }

    function _maxDeposit(address vault, address user) internal view returns (uint128) {
        Request memory request = requests[vault][user];
        return _calculateAssets(request.maxMint, vault, request.depositPrice);
    }

    /// @inheritdoc IInvestmentManager
    function maxMint(address vault, address user) public view returns (uint256 shares) {
        if (!_canTransfer(vault, address(escrow), user, 0)) return 0;
        return uint256(requests[vault][user].maxMint);
    }

    /// @inheritdoc IInvestmentManager
    function maxWithdraw(address vault, address user) public view returns (uint256 assets) {
        return uint256(requests[vault][user].maxWithdraw);
    }

    /// @inheritdoc IInvestmentManager
    function maxRedeem(address vault, address user) public view returns (uint256 shares) {
        Request memory request = requests[vault][user];
        return uint256(_calculateShares(request.maxWithdraw, vault, request.redeemPrice));
    }

    /// @inheritdoc IInvestmentManager
    function pendingDepositRequest(address vault, address user) public view returns (uint256 assets) {
        assets = uint256(requests[vault][user].pendingDeposit);
    }

    /// @inheritdoc IInvestmentManager
    function pendingRedeemRequest(address vault, address user) public view returns (uint256 shares) {
        shares = uint256(requests[vault][user].pendingRedeem);
    }

    /// @inheritdoc IInvestmentManager
    function pendingCancelDepositRequest(address vault, address user) public view returns (bool isPending) {
        isPending = requests[vault][user].pendingCancelDeposit;
    }

    /// @inheritdoc IInvestmentManager
    function pendingCancelRedeemRequest(address vault, address user) public view returns (bool isPending) {
        isPending = requests[vault][user].pendingCancelRedeem;
    }

    /// @inheritdoc IInvestmentManager
    function claimableCancelDepositRequest(address vault, address user) public view returns (uint256 assets) {
        assets = requests[vault][user].claimableCancelDeposit;
    }

    /// @inheritdoc IInvestmentManager
    function claimableCancelRedeemRequest(address vault, address user) public view returns (uint256 shares) {
        shares = requests[vault][user].claimableCancelRedeem;
    }

    /// @inheritdoc IInvestmentManager
    function priceLastUpdated(address vault) public view returns (uint64 lastUpdated) {
        VaultLike vault_ = VaultLike(vault);
        (, lastUpdated) = poolManager.getTrancheTokenPrice(vault_.poolId(), vault_.trancheId(), vault_.asset());
    }

    // --- Vault claim functions ---
    /// @inheritdoc IInvestmentManager
    function deposit(address vault, uint256 assets, address receiver, address owner)
        public
        auth
        returns (uint256 shares)
    {
        Request storage request = requests[vault][owner];
        uint128 shares_ = _calculateShares(assets.toUint128(), vault, request.depositPrice);
        _processDeposit(request, shares_, vault, receiver);
        shares = uint256(shares_);
    }

    /// @inheritdoc IInvestmentManager
    function mint(address vault, uint256 shares, address receiver, address owner)
        public
        auth
        returns (uint256 assets)
    {
        Request storage request = requests[vault][owner];
        _processDeposit(request, shares.toUint128(), vault, receiver);
        assets = uint256(_calculateAssets(shares.toUint128(), vault, request.depositPrice));
    }

    function _processDeposit(Request storage request, uint128 shares, address vault, address receiver) internal {
        require(shares != 0, "InvestmentManager/tranche-token-amount-is-zero");
        require(shares <= request.maxMint, "InvestmentManager/exceeds-deposit-limits");
        request.maxMint = request.maxMint - shares;
        require(
            IERC20(VaultLike(vault).share()).transferFrom(address(escrow), receiver, shares),
            "InvestmentManager/tranche-tokens-transfer-failed"
        );
    }

    /// @inheritdoc IInvestmentManager
    function redeem(address vault, uint256 shares, address receiver, address owner)
        public
        auth
        returns (uint256 assets)
    {
        Request storage request = requests[vault][owner];
        uint128 assets_ = _calculateAssets(shares.toUint128(), vault, request.redeemPrice);
        _processRedeem(request, assets_, vault, receiver);
        assets = uint256(assets_);
    }

    /// @inheritdoc IInvestmentManager
    function withdraw(address vault, uint256 assets, address receiver, address owner)
        public
        auth
        returns (uint256 shares)
    {
        Request storage request = requests[vault][owner];
        _processRedeem(request, assets.toUint128(), vault, receiver);
        shares = uint256(_calculateShares(assets.toUint128(), vault, request.redeemPrice));
    }

    function _processRedeem(Request storage request, uint128 assets, address vault, address receiver) internal {
        VaultLike vault_ = VaultLike(vault);
        require(assets != 0, "InvestmentManager/asset-amount-is-zero");
        require(assets <= request.maxWithdraw, "InvestmentManager/exceeds-redeem-limits");
        request.maxWithdraw = request.maxWithdraw - assets;
        SafeTransferLib.safeTransferFrom(vault_.asset(), address(escrow), receiver, assets);
    }

    /// @inheritdoc IInvestmentManager
    function claimCancelDepositRequest(address vault, address receiver, address owner)
        public
        auth
        returns (uint256 assets)
    {
        Request storage request = requests[vault][owner];
        assets = request.claimableCancelDeposit;
        request.claimableCancelDeposit = 0;
        SafeTransferLib.safeTransferFrom(VaultLike(vault).asset(), address(escrow), receiver, assets);
    }

    /// @inheritdoc IInvestmentManager
    function claimCancelRedeemRequest(address vault, address receiver, address owner)
        public
        auth
        returns (uint256 shares)
    {
        Request storage request = requests[vault][owner];
        shares = request.claimableCancelRedeem;
        request.claimableCancelRedeem = 0;
        require(
            IERC20(VaultLike(vault).share()).transferFrom(address(escrow), receiver, shares),
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
        if (assets == 0 || shares == 0) {
            return 0;
        }

        (uint8 assetDecimals, uint8 shareDecimals) = _getPoolDecimals(vault);
        price = _toPriceDecimals(assets, assetDecimals).mulDiv(
            10 ** PRICE_DECIMALS, _toPriceDecimals(shares, shareDecimals), MathLib.Rounding.Down
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

    /// @dev    Return the asset decimals and the share decimals for a given vault
    function _getPoolDecimals(address vault) internal view returns (uint8 assetDecimals, uint8 shareDecimals) {
        assetDecimals = IERC20Metadata(VaultLike(vault).asset()).decimals();
        shareDecimals = IERC20Metadata(VaultLike(vault).share()).decimals();
    }

    function _canTransfer(address vault, address from, address to, uint256 value) internal view returns (bool) {
        TrancheTokenLike share = TrancheTokenLike(VaultLike(vault).share());
        return share.checkTransferRestriction(from, to, value);
    }
}
