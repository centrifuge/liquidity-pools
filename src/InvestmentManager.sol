// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import {Auth} from "./Auth.sol";
import {CastLib} from "./libraries/CastLib.sol";
import {MathLib} from "./libraries/MathLib.sol";
import {SafeTransferLib} from "./libraries/SafeTransferLib.sol";
import {MessagesLib} from "./libraries/MessagesLib.sol";
import {BytesLib} from "./libraries/BytesLib.sol";
import {IERC20, IERC20Metadata} from "src/interfaces/IERC20.sol";
import {IPoolManager} from "src/interfaces/IPoolManager.sol";
import {IInvestmentManager, InvestmentState} from "src/interfaces/IInvestmentManager.sol";

interface GatewayLike {
    function send(bytes memory message) external;
}

interface TrancheTokenLike is IERC20 {
    function checkTransferRestriction(address from, address to, uint256 value) external view returns (bool);
    function mint(address user, uint256 value) external;
    function burn(address user, uint256 value) external;
}

interface LiquidityPoolLike is IERC20 {
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

/// @title  Investment Manager
/// @notice This is the main contract LiquidityPools interact with for
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

    mapping(address liquidityPool => mapping(address investor => InvestmentState)) public investments;

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
    function requestDeposit(address liquidityPool, uint256 currencyAmount, address receiver, address owner)
        public
        auth
        returns (bool)
    {
        LiquidityPoolLike lPool = LiquidityPoolLike(liquidityPool);
        uint128 _currencyAmount = currencyAmount.toUint128();
        require(_currencyAmount != 0, "InvestmentManager/zero-amount-not-allowed");

        uint64 poolId = lPool.poolId();
        address currency = lPool.asset();
        require(poolManager.isAllowedAsInvestmentCurrency(poolId, currency), "InvestmentManager/currency-not-allowed");

        require(_checkTransferRestriction(liquidityPool, address(0), owner, 0), "InvestmentManager/owner-is-restricted");
        require(
            _checkTransferRestriction(
                liquidityPool, address(0), receiver, convertToShares(liquidityPool, currencyAmount)
            ),
            "InvestmentManager/transfer-not-allowed"
        );

        InvestmentState storage state = investments[liquidityPool][receiver];
        require(state.pendingCancelDepositRequest != true, "InvestmentManager/cancellation-is-pending");

        state.pendingDepositRequest = state.pendingDepositRequest + _currencyAmount;
        state.exists = true;

        gateway.send(
            abi.encodePacked(
                uint8(MessagesLib.Call.IncreaseInvestOrder),
                poolId,
                lPool.trancheId(),
                receiver,
                poolManager.currencyAddressToId(currency),
                _currencyAmount
            )
        );

        return true;
    }

    /// @inheritdoc IInvestmentManager
    function requestRedeem(address liquidityPool, uint256 trancheTokenAmount, address receiver, address /* owner */ )
        public
        auth
        returns (bool)
    {
        uint128 _trancheTokenAmount = trancheTokenAmount.toUint128();
        require(_trancheTokenAmount != 0, "InvestmentManager/zero-amount-not-allowed");
        LiquidityPoolLike lPool = LiquidityPoolLike(liquidityPool);

        // You cannot redeem using a disallowed investment currency, instead another LP will have to be used
        require(
            poolManager.isAllowedAsInvestmentCurrency(lPool.poolId(), lPool.asset()),
            "InvestmentManager/currency-not-allowed"
        );

        require(
            _checkTransferRestriction(
                liquidityPool, receiver, address(escrow), convertToAssets(liquidityPool, trancheTokenAmount)
            ),
            "InvestmentManager/transfer-not-allowed"
        );

        return _processRedeemRequest(liquidityPool, _trancheTokenAmount, receiver);
    }

    function _processRedeemRequest(address liquidityPool, uint128 trancheTokenAmount, address owner)
        internal
        returns (bool)
    {
        LiquidityPoolLike lPool = LiquidityPoolLike(liquidityPool);
        InvestmentState storage state = investments[liquidityPool][owner];
        require(state.pendingCancelRedeemRequest != true, "InvestmentManager/cancellation-is-pending");

        state.pendingRedeemRequest = state.pendingRedeemRequest + trancheTokenAmount;
        state.exists = true;

        gateway.send(
            abi.encodePacked(
                uint8(MessagesLib.Call.IncreaseRedeemOrder),
                lPool.poolId(),
                lPool.trancheId(),
                owner,
                poolManager.currencyAddressToId(lPool.asset()),
                trancheTokenAmount
            )
        );

        return true;
    }

    /// @inheritdoc IInvestmentManager
    function cancelDepositRequest(address liquidityPool, address owner) public auth {
        LiquidityPoolLike _liquidityPool = LiquidityPoolLike(liquidityPool);

        InvestmentState storage state = investments[liquidityPool][owner];
        require(state.pendingCancelDepositRequest != true, "InvestmentManager/cancellation-is-pending");
        state.pendingCancelDepositRequest = true;

        gateway.send(
            abi.encodePacked(
                uint8(MessagesLib.Call.CancelInvestOrder),
                _liquidityPool.poolId(),
                _liquidityPool.trancheId(),
                owner.toBytes32(),
                poolManager.currencyAddressToId(_liquidityPool.asset())
            )
        );
    }

    /// @inheritdoc IInvestmentManager
    function cancelRedeemRequest(address liquidityPool, address owner) public auth {
        LiquidityPoolLike _liquidityPool = LiquidityPoolLike(liquidityPool);
        uint256 approximateTrancheTokensPayout = pendingRedeemRequest(liquidityPool, owner);
        require(
            _checkTransferRestriction(liquidityPool, address(0), owner, approximateTrancheTokensPayout),
            "InvestmentManager/transfer-not-allowed"
        );

        InvestmentState storage state = investments[liquidityPool][owner];
        require(state.pendingCancelRedeemRequest != true, "InvestmentManager/cancellation-is-pending");
        state.pendingCancelRedeemRequest = true;

        gateway.send(
            abi.encodePacked(
                uint8(MessagesLib.Call.CancelRedeemOrder),
                _liquidityPool.poolId(),
                _liquidityPool.trancheId(),
                owner.toBytes32(),
                poolManager.currencyAddressToId(_liquidityPool.asset())
            )
        );
    }

    // --- Incoming message handling ---
    /// @inheritdoc IInvestmentManager
    function handle(bytes calldata message) public auth {
        MessagesLib.Call call = MessagesLib.messageType(message);

        if (call == MessagesLib.Call.ExecutedCollectInvest) {
            handleExecutedCollectInvest(
                message.toUint64(1),
                message.toBytes16(9),
                message.toAddress(25),
                message.toUint128(57),
                message.toUint128(73),
                message.toUint128(89),
                message.toUint128(105)
            );
        } else if (call == MessagesLib.Call.ExecutedCollectRedeem) {
            handleExecutedCollectRedeem(
                message.toUint64(1),
                message.toBytes16(9),
                message.toAddress(25),
                message.toUint128(57),
                message.toUint128(73),
                message.toUint128(89)
            );
        } else if (call == MessagesLib.Call.ExecutedDecreaseInvestOrder) {
            handleExecutedDecreaseInvestOrder(
                message.toUint64(1),
                message.toBytes16(9),
                message.toAddress(25),
                message.toUint128(57),
                message.toUint128(73),
                message.toUint128(89)
            );
        } else if (call == MessagesLib.Call.ExecutedDecreaseRedeemOrder) {
            handleExecutedDecreaseRedeemOrder(
                message.toUint64(1),
                message.toBytes16(9),
                message.toAddress(25),
                message.toUint128(57),
                message.toUint128(73),
                message.toUint128(89)
            );
        } else if (call == MessagesLib.Call.TriggerIncreaseRedeemOrder) {
            handleTriggerIncreaseRedeemOrder(
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
    function handleExecutedCollectInvest(
        uint64 poolId,
        bytes16 trancheId,
        address user,
        uint128 currencyId,
        uint128 currencyPayout,
        uint128 trancheTokenPayout,
        uint128 fulfilledInvestOrder
    ) public auth {
        address liquidityPool = poolManager.getLiquidityPool(poolId, trancheId, currencyId);

        InvestmentState storage state = investments[liquidityPool][user];
        state.depositPrice = _calculatePrice(
            liquidityPool, _maxDeposit(liquidityPool, user) + currencyPayout, state.maxMint + trancheTokenPayout
        );
        state.maxMint = state.maxMint + trancheTokenPayout;
        state.pendingDepositRequest =
            state.pendingDepositRequest > fulfilledInvestOrder ? state.pendingDepositRequest - fulfilledInvestOrder : 0;

        if (state.pendingDepositRequest == 0) state.pendingCancelDepositRequest = false;

        // Mint to escrow. Recipient can claim by calling withdraw / redeem
        TrancheTokenLike trancheToken = TrancheTokenLike(LiquidityPoolLike(liquidityPool).share());
        trancheToken.mint(address(escrow), trancheTokenPayout);

        LiquidityPoolLike(liquidityPool).emitDepositClaimable(user, currencyPayout, trancheTokenPayout);
    }

    /// @inheritdoc IInvestmentManager
    function handleExecutedCollectRedeem(
        uint64 poolId,
        bytes16 trancheId,
        address user,
        uint128 currencyId,
        uint128 currencyPayout,
        uint128 trancheTokenPayout
    ) public auth {
        address liquidityPool = poolManager.getLiquidityPool(poolId, trancheId, currencyId);

        InvestmentState storage state = investments[liquidityPool][user];
        require(state.exists == true, "InvestmentManager/non-existent-user");

        // Calculate new weighted average redeem price and update order book values
        state.redeemPrice = _calculatePrice(
            liquidityPool,
            state.maxWithdraw + currencyPayout,
            ((maxRedeem(liquidityPool, user)) + trancheTokenPayout).toUint128()
        );
        state.maxWithdraw = state.maxWithdraw + currencyPayout;
        state.pendingRedeemRequest =
            state.pendingRedeemRequest > trancheTokenPayout ? state.pendingRedeemRequest - trancheTokenPayout : 0;

        if (state.pendingRedeemRequest == 0) state.pendingCancelRedeemRequest = false;

        // Burn redeemed tranche tokens from escrow
        TrancheTokenLike trancheToken = TrancheTokenLike(LiquidityPoolLike(liquidityPool).share());
        trancheToken.burn(address(escrow), trancheTokenPayout);

        LiquidityPoolLike(liquidityPool).emitRedeemClaimable(user, currencyPayout, trancheTokenPayout);
    }

    /// @inheritdoc IInvestmentManager
    function handleExecutedDecreaseInvestOrder(
        uint64 poolId,
        bytes16 trancheId,
        address user,
        uint128 currencyId,
        uint128 currencyPayout,
        uint128 decreasedInvestOrder
    ) public auth {
        address liquidityPool = poolManager.getLiquidityPool(poolId, trancheId, currencyId);

        InvestmentState storage state = investments[liquidityPool][user];
        require(state.exists == true, "InvestmentManager/non-existent-user");

        state.claimableCancelDepositRequest = state.claimableCancelDepositRequest + currencyPayout;
        state.pendingDepositRequest =
            state.pendingDepositRequest > decreasedInvestOrder ? state.pendingDepositRequest - decreasedInvestOrder : 0;

        if (state.pendingDepositRequest == 0) state.pendingCancelDepositRequest = false;
    }

    /// @inheritdoc IInvestmentManager
    function handleExecutedDecreaseRedeemOrder(
        uint64 poolId,
        bytes16 trancheId,
        address user,
        uint128 currencyId,
        uint128 trancheTokenPayout,
        uint128 decreasedRedeemOrder
    ) public auth {
        address liquidityPool = poolManager.getLiquidityPool(poolId, trancheId, currencyId);
        InvestmentState storage state = investments[liquidityPool][user];

        state.claimableCancelRedeemRequest = state.claimableCancelRedeemRequest + trancheTokenPayout;
        state.pendingRedeemRequest =
            state.pendingRedeemRequest > decreasedRedeemOrder ? state.pendingRedeemRequest - decreasedRedeemOrder : 0;

        if (state.pendingRedeemRequest == 0) state.pendingCancelRedeemRequest = false;
    }

    /// @inheritdoc IInvestmentManager
    function handleTriggerIncreaseRedeemOrder(
        uint64 poolId,
        bytes16 trancheId,
        address user,
        uint128 currencyId,
        uint128 trancheTokenAmount
    ) public auth {
        require(trancheTokenAmount != 0, "InvestmentManager/tranche-token-amount-is-zero");
        address liquidityPool = poolManager.getLiquidityPool(poolId, trancheId, currencyId);

        // If there's any unclaimed deposits, claim those first
        InvestmentState storage state = investments[liquidityPool][user];
        uint128 tokensToTransfer = trancheTokenAmount;
        if (state.maxMint >= trancheTokenAmount) {
            // The full redeem request is covered by the claimable amount
            tokensToTransfer = 0;
            state.maxMint = state.maxMint - trancheTokenAmount;
        } else if (state.maxMint > 0) {
            // The redeem request is only partially covered by the claimable amount
            tokensToTransfer = trancheTokenAmount - state.maxMint;
            state.maxMint = 0;
        }

        require(
            _processRedeemRequest(liquidityPool, trancheTokenAmount, user), "InvestmentManager/failed-redeem-request"
        );

        // Transfer the tranche token amount that was not covered by tokens still in escrow for claims,
        // from user to escrow (lock tranche tokens in escrow)
        if (tokensToTransfer > 0) {
            require(
                AuthTransferLike(address(LiquidityPoolLike(liquidityPool).share())).authTransferFrom(
                    user, address(escrow), tokensToTransfer
                ),
                "InvestmentManager/transfer-failed"
            );
        }
        emit TriggerIncreaseRedeemOrder(
            poolId, trancheId, user, poolManager.currencyIdToAddress(currencyId), trancheTokenAmount
        );
    }

    // --- View functions ---
    /// @inheritdoc IInvestmentManager
    function convertToShares(address liquidityPool, uint256 _assets) public view returns (uint256 shares) {
        LiquidityPoolLike liquidityPool_ = LiquidityPoolLike(liquidityPool);
        (uint128 latestPrice,) = poolManager.getTrancheTokenPrice(
            liquidityPool_.poolId(), liquidityPool_.trancheId(), liquidityPool_.asset()
        );
        shares = uint256(_calculateTrancheTokenAmount(_assets.toUint128(), liquidityPool, latestPrice));
    }

    /// @inheritdoc IInvestmentManager
    function convertToAssets(address liquidityPool, uint256 _shares) public view returns (uint256 assets) {
        LiquidityPoolLike liquidityPool_ = LiquidityPoolLike(liquidityPool);
        (uint128 latestPrice,) = poolManager.getTrancheTokenPrice(
            liquidityPool_.poolId(), liquidityPool_.trancheId(), liquidityPool_.asset()
        );
        assets = uint256(_calculateCurrencyAmount(_shares.toUint128(), liquidityPool, latestPrice));
    }

    /// @inheritdoc IInvestmentManager
    function maxDeposit(address liquidityPool, address user) public view returns (uint256) {
        if (!_checkTransferRestriction(liquidityPool, address(escrow), user, 0)) return 0;
        return uint256(_maxDeposit(liquidityPool, user));
    }

    function _maxDeposit(address liquidityPool, address user) internal view returns (uint128) {
        InvestmentState memory state = investments[liquidityPool][user];
        return _calculateCurrencyAmount(state.maxMint, liquidityPool, state.depositPrice);
    }

    /// @inheritdoc IInvestmentManager
    function maxMint(address liquidityPool, address user) public view returns (uint256 trancheTokenAmount) {
        if (!_checkTransferRestriction(liquidityPool, address(escrow), user, 0)) return 0;
        return uint256(investments[liquidityPool][user].maxMint);
    }

    /// @inheritdoc IInvestmentManager
    function maxWithdraw(address liquidityPool, address user) public view returns (uint256 currencyAmount) {
        return uint256(investments[liquidityPool][user].maxWithdraw);
    }

    /// @inheritdoc IInvestmentManager
    function maxRedeem(address liquidityPool, address user) public view returns (uint256 trancheTokenAmount) {
        InvestmentState memory state = investments[liquidityPool][user];
        return uint256(_calculateTrancheTokenAmount(state.maxWithdraw, liquidityPool, state.redeemPrice));
    }

    /// @inheritdoc IInvestmentManager
    function pendingDepositRequest(address liquidityPool, address user) public view returns (uint256 currencyAmount) {
        currencyAmount = uint256(investments[liquidityPool][user].pendingDepositRequest);
    }

    /// @inheritdoc IInvestmentManager
    function pendingRedeemRequest(address liquidityPool, address user)
        public
        view
        returns (uint256 trancheTokenAmount)
    {
        trancheTokenAmount = uint256(investments[liquidityPool][user].pendingRedeemRequest);
    }

    /// @inheritdoc IInvestmentManager
    function pendingCancelDepositRequest(address liquidityPool, address user) public view returns (bool isPending) {
        isPending = investments[liquidityPool][user].pendingCancelDepositRequest;
    }

    /// @inheritdoc IInvestmentManager
    function pendingCancelRedeemRequest(address liquidityPool, address user) public view returns (bool isPending) {
        isPending = investments[liquidityPool][user].pendingCancelRedeemRequest;
    }

    /// @inheritdoc IInvestmentManager
    function claimableCancelDepositRequest(address liquidityPool, address user)
        public
        view
        returns (uint256 currencyAmount)
    {
        currencyAmount = investments[liquidityPool][user].claimableCancelDepositRequest;
    }

    /// @inheritdoc IInvestmentManager
    function claimableCancelRedeemRequest(address liquidityPool, address user)
        public
        view
        returns (uint256 trancheTokenAmount)
    {
        trancheTokenAmount = investments[liquidityPool][user].claimableCancelRedeemRequest;
    }

    /// @inheritdoc IInvestmentManager
    function exchangeRateLastUpdated(address liquidityPool) public view returns (uint64 lastUpdated) {
        LiquidityPoolLike liquidityPool_ = LiquidityPoolLike(liquidityPool);
        (, lastUpdated) = poolManager.getTrancheTokenPrice(
            liquidityPool_.poolId(), liquidityPool_.trancheId(), liquidityPool_.asset()
        );
    }

    // --- Liquidity Pool processing functions ---
    /// @inheritdoc IInvestmentManager
    function deposit(address liquidityPool, uint256 currencyAmount, address receiver, address owner)
        public
        auth
        returns (uint256 trancheTokenAmount)
    {
        InvestmentState storage state = investments[liquidityPool][owner];
        uint128 trancheTokenAmount_ =
            _calculateTrancheTokenAmount(currencyAmount.toUint128(), liquidityPool, state.depositPrice);
        _processDeposit(state, trancheTokenAmount_, liquidityPool, receiver);
        trancheTokenAmount = uint256(trancheTokenAmount_);
    }

    /// @inheritdoc IInvestmentManager
    function mint(address liquidityPool, uint256 trancheTokenAmount, address receiver, address owner)
        public
        auth
        returns (uint256 currencyAmount)
    {
        InvestmentState storage state = investments[liquidityPool][owner];
        _processDeposit(state, trancheTokenAmount.toUint128(), liquidityPool, receiver);
        currencyAmount =
            uint256(_calculateCurrencyAmount(trancheTokenAmount.toUint128(), liquidityPool, state.depositPrice));
    }

    function _processDeposit(
        InvestmentState storage state,
        uint128 trancheTokenAmount,
        address liquidityPool,
        address receiver
    ) internal {
        require(trancheTokenAmount != 0, "InvestmentManager/tranche-token-amount-is-zero");
        require(trancheTokenAmount <= state.maxMint, "InvestmentManager/exceeds-deposit-limits");
        state.maxMint = state.maxMint - trancheTokenAmount;
        require(
            IERC20(LiquidityPoolLike(liquidityPool).share()).transferFrom(address(escrow), receiver, trancheTokenAmount),
            "InvestmentManager/tranche-tokens-transfer-failed"
        );
    }

    /// @inheritdoc IInvestmentManager
    function redeem(address liquidityPool, uint256 trancheTokenAmount, address receiver, address owner)
        public
        auth
        returns (uint256 currencyAmount)
    {
        InvestmentState storage state = investments[liquidityPool][owner];
        uint128 currencyAmount_ =
            _calculateCurrencyAmount(trancheTokenAmount.toUint128(), liquidityPool, state.redeemPrice);
        _processRedeem(state, currencyAmount_, liquidityPool, receiver);
        currencyAmount = uint256(currencyAmount_);
    }

    /// @inheritdoc IInvestmentManager
    function withdraw(address liquidityPool, uint256 currencyAmount, address receiver, address owner)
        public
        auth
        returns (uint256 trancheTokenAmount)
    {
        InvestmentState storage state = investments[liquidityPool][owner];
        _processRedeem(state, currencyAmount.toUint128(), liquidityPool, receiver);
        trancheTokenAmount =
            uint256(_calculateTrancheTokenAmount(currencyAmount.toUint128(), liquidityPool, state.redeemPrice));
    }

    function _processRedeem(
        InvestmentState storage state,
        uint128 currencyAmount,
        address liquidityPool,
        address receiver
    ) internal {
        LiquidityPoolLike lPool = LiquidityPoolLike(liquidityPool);
        require(currencyAmount != 0, "InvestmentManager/currency-amount-is-zero");
        require(currencyAmount <= state.maxWithdraw, "InvestmentManager/exceeds-redeem-limits");
        state.maxWithdraw = state.maxWithdraw - currencyAmount;
        SafeTransferLib.safeTransferFrom(lPool.asset(), address(escrow), receiver, currencyAmount);
    }

    /// @inheritdoc IInvestmentManager
    function claimCancelDepositRequest(address liquidityPool, address receiver, address owner)
        public
        auth
        returns (uint256 currencyAmount)
    {
        InvestmentState storage state = investments[liquidityPool][owner];
        currencyAmount = state.claimableCancelDepositRequest;
        state.claimableCancelDepositRequest = 0;
        SafeTransferLib.safeTransferFrom(
            LiquidityPoolLike(liquidityPool).asset(), address(escrow), receiver, currencyAmount
        );
    }

    /// @inheritdoc IInvestmentManager
    function claimCancelRedeemRequest(address liquidityPool, address receiver, address owner)
        public
        auth
        returns (uint256 trancheTokenAmount)
    {
        InvestmentState storage state = investments[liquidityPool][owner];
        trancheTokenAmount = state.claimableCancelRedeemRequest;
        state.claimableCancelRedeemRequest = 0;
        require(
            IERC20(LiquidityPoolLike(liquidityPool).share()).transferFrom(address(escrow), receiver, trancheTokenAmount),
            "InvestmentManager/tranche-tokens-transfer-failed"
        );
    }

    // --- Helpers ---
    function _calculateTrancheTokenAmount(uint128 currencyAmount, address liquidityPool, uint256 price)
        internal
        view
        returns (uint128 trancheTokenAmount)
    {
        if (price == 0 || currencyAmount == 0) {
            trancheTokenAmount = 0;
        } else {
            (uint8 currencyDecimals, uint8 trancheTokenDecimals) = _getPoolDecimals(liquidityPool);

            uint256 trancheTokenAmountInPriceDecimals = _toPriceDecimals(currencyAmount, currencyDecimals).mulDiv(
                10 ** PRICE_DECIMALS, price, MathLib.Rounding.Down
            );

            trancheTokenAmount = _fromPriceDecimals(trancheTokenAmountInPriceDecimals, trancheTokenDecimals);
        }
    }

    function _calculateCurrencyAmount(uint128 trancheTokenAmount, address liquidityPool, uint256 price)
        internal
        view
        returns (uint128 currencyAmount)
    {
        if (price == 0 || trancheTokenAmount == 0) {
            currencyAmount = 0;
        } else {
            (uint8 currencyDecimals, uint8 trancheTokenDecimals) = _getPoolDecimals(liquidityPool);

            uint256 currencyAmountInPriceDecimals = _toPriceDecimals(trancheTokenAmount, trancheTokenDecimals).mulDiv(
                price, 10 ** PRICE_DECIMALS, MathLib.Rounding.Down
            );

            currencyAmount = _fromPriceDecimals(currencyAmountInPriceDecimals, currencyDecimals);
        }
    }

    function _calculatePrice(address liquidityPool, uint128 currencyAmount, uint128 trancheTokenAmount)
        internal
        view
        returns (uint256 price)
    {
        (uint8 currencyDecimals, uint8 trancheTokenDecimals) = _getPoolDecimals(liquidityPool);
        price = _calculatePrice(
            _toPriceDecimals(currencyAmount, currencyDecimals),
            _toPriceDecimals(trancheTokenAmount, trancheTokenDecimals)
        );
    }

    function _calculatePrice(uint256 currencyAmountInPriceDecimals, uint256 trancheTokenAmountInPriceDecimals)
        internal
        pure
        returns (uint256 price)
    {
        if (currencyAmountInPriceDecimals == 0 || trancheTokenAmountInPriceDecimals == 0) {
            return 0;
        }

        price = currencyAmountInPriceDecimals.mulDiv(
            10 ** PRICE_DECIMALS, trancheTokenAmountInPriceDecimals, MathLib.Rounding.Down
        );
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

    /// @dev    Return the currency decimals and the tranche token decimals for a given liquidityPool
    function _getPoolDecimals(address liquidityPool)
        internal
        view
        returns (uint8 currencyDecimals, uint8 trancheTokenDecimals)
    {
        currencyDecimals = IERC20Metadata(LiquidityPoolLike(liquidityPool).asset()).decimals();
        trancheTokenDecimals = IERC20Metadata(LiquidityPoolLike(liquidityPool).share()).decimals();
    }

    function _checkTransferRestriction(address liquidityPool, address from, address to, uint256 value)
        internal
        view
        returns (bool)
    {
        TrancheTokenLike trancheToken = TrancheTokenLike(LiquidityPoolLike(liquidityPool).share());
        return trancheToken.checkTransferRestriction(from, to, value);
    }
}
