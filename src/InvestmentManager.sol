// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import {Auth} from "./Auth.sol";
import {CastLib} from "./libraries/CastLib.sol";
import {MathLib} from "./libraries/MathLib.sol";
import {SafeTransferLib} from "./libraries/SafeTransferLib.sol";
import {MessagesLib} from "./libraries/MessagesLib.sol";

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

interface LiquidityPoolLike is ERC20Like {
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
    function currencyIdToAddress(uint128 currencyId) external view returns (address);
    function currencyAddressToId(address addr) external view returns (uint128);
    function getTrancheToken(uint64 poolId, bytes16 trancheId) external view returns (address);
    function getTrancheTokenPrice(uint64 poolId, bytes16 trancheId, address currencyAddress)
        external
        view
        returns (uint256 price, uint64 computedAt);
    function getLiquidityPool(uint64 poolId, bytes16 trancheId, uint128 currencyId) external view returns (address);
    function isAllowedAsInvestmentCurrency(uint64 poolId, address currencyAddress) external view returns (bool);
}

interface UserEscrowLike {
    function transferIn(address token, address source, address destination, uint256 amount) external;
    function transferOut(address token, address owner, address destination, uint256 amount) external;
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
    using MathLib for uint256;
    using CastLib for *;

    /// @dev Prices are fixed-point integers with 18 decimals
    uint8 internal constant PRICE_DECIMALS = 18;

    address public immutable escrow;
    UserEscrowLike public immutable userEscrow;

    GatewayLike public gateway;
    PoolManagerLike public poolManager;

    mapping(address liquidityPool => mapping(address investor => InvestmentState)) public investments;

    // --- Events ---
    event File(bytes32 indexed what, address data);
    event TriggerIncreaseRedeemOrder(
        uint64 indexed poolId, bytes16 indexed trancheId, address user, address currency, uint128 trancheTokenAmount
    );

    constructor(address escrow_, address userEscrow_) {
        escrow = escrow_;
        userEscrow = UserEscrowLike(userEscrow_);

        wards[msg.sender] = 1;
        emit Rely(msg.sender);
    }

    /// @dev Gateway must be msg.sender for incoming messages
    modifier onlyGateway() {
        require(msg.sender == address(gateway), "InvestmentManager/not-the-gateway");
        _;
    }

    // --- Administration ---
    function file(bytes32 what, address data) external auth {
        if (what == "gateway") gateway = GatewayLike(data);
        else if (what == "poolManager") poolManager = PoolManagerLike(data);
        else revert("InvestmentManager/file-unrecognized-param");
        emit File(what, data);
    }

    // --- Outgoing message handling ---
    /// @notice Liquidity pools have to request investments from Centrifuge before
    ///         tranche tokens can be minted. The deposit requests are added to the order book
    ///         on Centrifuge. Once the next epoch is executed on Centrifuge, liquidity pools can
    ///         proceed with tranche token payouts in case their orders got fulfilled.
    /// @dev    The user currency amount required to fulfill the deposit request have to be locked,
    ///         even though the tranche token payout can only happen after epoch execution.
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

    /// @notice Request tranche token redemption. Liquidity pools have to request redemptions
    ///         from Centrifuge before actual currency payouts can be done. The redemption
    ///         requests are added to the order book on Centrifuge. Once the next epoch is
    ///         executed on Centrifuge, liquidity pools can proceed with currency payouts
    ///         in case their orders got fulfilled.
    /// @dev    The user tranche tokens required to fulfill the redemption request have to be locked,
    ///         even though the currency payout can only happen after epoch execution.
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
    function handleExecutedCollectInvest(
        uint64 poolId,
        bytes16 trancheId,
        address user,
        uint128 currencyId,
        uint128 currencyPayout,
        uint128 trancheTokenPayout,
        uint128 remainingInvestOrder
    ) public onlyGateway {
        address liquidityPool = poolManager.getLiquidityPool(poolId, trancheId, currencyId);

        InvestmentState storage state = investments[liquidityPool][user];
        state.depositPrice = _calculatePrice(
            liquidityPool, _maxDeposit(liquidityPool, user) + currencyPayout, state.maxMint + trancheTokenPayout
        );
        state.maxMint = state.maxMint + trancheTokenPayout;
        state.pendingDepositRequest = remainingInvestOrder;

        // Mint to escrow. Recipient can claim by calling withdraw / redeem
        ERC20Like trancheToken = ERC20Like(LiquidityPoolLike(liquidityPool).share());
        trancheToken.mint(address(escrow), trancheTokenPayout);

        LiquidityPoolLike(liquidityPool).emitDepositClaimable(user, currencyPayout, trancheTokenPayout);
    }

    function handleExecutedCollectRedeem(
        uint64 poolId,
        bytes16 trancheId,
        address user,
        uint128 currencyId,
        uint128 currencyPayout,
        uint128 trancheTokenPayout,
        uint128 remainingRedeemOrder
    ) public onlyGateway {
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
        state.pendingRedeemRequest = remainingRedeemOrder;

        // Transfer currency to user escrow to claim on withdraw/redeem,
        // and burn redeemed tranche tokens from escrow
        userEscrow.transferIn(poolManager.currencyIdToAddress(currencyId), address(escrow), user, currencyPayout);
        ERC20Like trancheToken = ERC20Like(LiquidityPoolLike(liquidityPool).share());
        trancheToken.burn(address(escrow), trancheTokenPayout);

        LiquidityPoolLike(liquidityPool).emitRedeemClaimable(user, currencyPayout, trancheTokenPayout);
    }

    function handleExecutedDecreaseInvestOrder(
        uint64 poolId,
        bytes16 trancheId,
        address user,
        uint128 currencyId,
        uint128 currencyPayout,
        uint128 remainingInvestOrder
    ) public onlyGateway {
        address liquidityPool = poolManager.getLiquidityPool(poolId, trancheId, currencyId);

        InvestmentState storage state = investments[liquidityPool][user];
        require(state.exists == true, "InvestmentManager/non-existent-user");

        // Calculating the price with both payouts as currencyPayout
        // leads to an effective redeem price of 1.0 and thus the user actually receiving
        // exactly currencyPayout on both deposit() and mint()
        (uint8 currencyDecimals, uint8 trancheTokenDecimals) = _getPoolDecimals(liquidityPool);
        uint256 currencyPayoutInPriceDecimals = _toPriceDecimals(currencyPayout, currencyDecimals);
        state.redeemPrice = _calculatePrice(
            _toPriceDecimals(state.maxWithdraw, currencyDecimals) + currencyPayoutInPriceDecimals,
            _toPriceDecimals(maxRedeem(liquidityPool, user).toUint128(), trancheTokenDecimals)
                + currencyPayoutInPriceDecimals
        );

        state.maxWithdraw = state.maxWithdraw + currencyPayout;
        state.pendingDepositRequest = remainingInvestOrder;

        if (remainingInvestOrder == 0) state.pendingCancelDepositRequest = false;

        // Transfer currency amount to userEscrow
        userEscrow.transferIn(poolManager.currencyIdToAddress(currencyId), address(escrow), user, currencyPayout);

        LiquidityPoolLike(liquidityPool).emitRedeemClaimable(user, currencyPayout, currencyPayout);
    }

    /// @dev Compared to handleExecutedDecreaseInvestOrder, there is no
    ///      transfer of currency in this function because they
    ///      can stay in the Escrow, ready to be claimed on deposit/mint.
    function handleExecutedDecreaseRedeemOrder(
        uint64 poolId,
        bytes16 trancheId,
        address user,
        uint128 currencyId,
        uint128 trancheTokenPayout,
        uint128 remainingRedeemOrder
    ) public onlyGateway {
        address liquidityPool = poolManager.getLiquidityPool(poolId, trancheId, currencyId);
        InvestmentState storage state = investments[liquidityPool][user];

        // Calculating the price with both payouts as trancheTokenPayout
        // leads to an effective redeem price of 1.0 and thus the user actually receiving
        // exactly trancheTokenPayout on both deposit() and mint()
        (uint8 currencyDecimals, uint8 trancheTokenDecimals) = _getPoolDecimals(liquidityPool);
        uint256 trancheTokenPayoutInPriceDecimals = _toPriceDecimals(trancheTokenPayout, trancheTokenDecimals);
        state.depositPrice = _calculatePrice(
            _toPriceDecimals(_maxDeposit(liquidityPool, user), currencyDecimals).toUint128()
                + trancheTokenPayoutInPriceDecimals,
            _toPriceDecimals(state.maxMint, trancheTokenDecimals) + trancheTokenPayoutInPriceDecimals
        );

        state.maxMint = state.maxMint + trancheTokenPayout;
        state.pendingRedeemRequest = remainingRedeemOrder;

        if (remainingRedeemOrder == 0) state.pendingCancelRedeemRequest = false;

        LiquidityPoolLike(liquidityPool).emitRedeemClaimable(user, trancheTokenPayout, trancheTokenPayout);
    }

    function handleTriggerIncreaseRedeemOrder(
        uint64 poolId,
        bytes16 trancheId,
        address user,
        uint128 currencyId,
        uint128 trancheTokenAmount
    ) public onlyGateway {
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
    function convertToShares(address liquidityPool, uint256 _assets) public view returns (uint256 shares) {
        LiquidityPoolLike liquidityPool_ = LiquidityPoolLike(liquidityPool);
        (uint256 latestPrice,) = poolManager.getTrancheTokenPrice(
            liquidityPool_.poolId(), liquidityPool_.trancheId(), liquidityPool_.asset()
        );
        shares = uint256(_calculateTrancheTokenAmount(_assets.toUint128(), liquidityPool, latestPrice));
    }

    function convertToAssets(address liquidityPool, uint256 _shares) public view returns (uint256 assets) {
        LiquidityPoolLike liquidityPool_ = LiquidityPoolLike(liquidityPool);
        (uint256 latestPrice,) = poolManager.getTrancheTokenPrice(
            liquidityPool_.poolId(), liquidityPool_.trancheId(), liquidityPool_.asset()
        );
        assets = uint256(_calculateCurrencyAmount(_shares.toUint128(), liquidityPool, latestPrice));
    }

    function maxDeposit(address liquidityPool, address user) public view returns (uint256) {
        if (!_checkTransferRestriction(liquidityPool, address(escrow), user, 0)) return 0;
        return uint256(_maxDeposit(liquidityPool, user));
    }

    function _maxDeposit(address liquidityPool, address user) internal view returns (uint128) {
        InvestmentState memory state = investments[liquidityPool][user];
        return _calculateCurrencyAmount(state.maxMint, liquidityPool, state.depositPrice);
    }

    function maxMint(address liquidityPool, address user) public view returns (uint256 trancheTokenAmount) {
        if (!_checkTransferRestriction(liquidityPool, address(escrow), user, 0)) return 0;
        return uint256(investments[liquidityPool][user].maxMint);
    }

    function maxWithdraw(address liquidityPool, address user) public view returns (uint256 currencyAmount) {
        return uint256(investments[liquidityPool][user].maxWithdraw);
    }

    function maxRedeem(address liquidityPool, address user) public view returns (uint256 trancheTokenAmount) {
        InvestmentState memory state = investments[liquidityPool][user];
        return uint256(_calculateTrancheTokenAmount(state.maxWithdraw, liquidityPool, state.redeemPrice));
    }

    function pendingDepositRequest(address liquidityPool, address user) public view returns (uint256 currencyAmount) {
        currencyAmount = uint256(investments[liquidityPool][user].pendingDepositRequest);
    }

    function pendingRedeemRequest(address liquidityPool, address user)
        public
        view
        returns (uint256 trancheTokenAmount)
    {
        trancheTokenAmount = uint256(investments[liquidityPool][user].pendingRedeemRequest);
    }

    function pendingCancelDepositRequest(address liquidityPool, address user) public view returns (bool isPending) {
        isPending = investments[liquidityPool][user].pendingCancelDepositRequest;
    }

    function pendingCancelRedeemRequest(address liquidityPool, address user) public view returns (bool isPending) {
        isPending = investments[liquidityPool][user].pendingCancelRedeemRequest;
    }

    function exchangeRateLastUpdated(address liquidityPool) public view returns (uint64 lastUpdated) {
        LiquidityPoolLike liquidityPool_ = LiquidityPoolLike(liquidityPool);
        (, lastUpdated) = poolManager.getTrancheTokenPrice(
            liquidityPool_.poolId(), liquidityPool_.trancheId(), liquidityPool_.asset()
        );
    }

    // --- Liquidity Pool processing functions ---
    /// @notice Processes owner's currency deposit / investment after the epoch has been executed on Centrifuge.
    ///         The currency required to fulfill the invest order is already locked in escrow upon calling
    ///         requestDeposit.
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

    /// @notice Processes owner's currency deposit / investment after the epoch has been executed on Centrifuge.
    ///         The currency required to fulfill the invest order is already locked in escrow upon calling
    ///         requestDeposit.
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
            ERC20Like(LiquidityPoolLike(liquidityPool).share()).transferFrom(
                address(escrow), receiver, trancheTokenAmount
            ),
            "InvestmentManager/tranche-tokens-transfer-failed"
        );
    }

    /// @dev    Processes owner's tranche Token redemption after the epoch has been executed on Centrifuge.
    ///         The trancheTokenAmount required to fulfill the redemption order was already locked in escrow
    ///         upon calling requestRedeem.
    function redeem(address liquidityPool, uint256 trancheTokenAmount, address receiver, address owner)
        public
        auth
        returns (uint256 currencyAmount)
    {
        InvestmentState storage state = investments[liquidityPool][owner];
        uint128 currencyAmount_ =
            _calculateCurrencyAmount(trancheTokenAmount.toUint128(), liquidityPool, state.redeemPrice);
        _processRedeem(state, currencyAmount_, liquidityPool, receiver, owner);
        currencyAmount = uint256(currencyAmount_);
    }

    /// @dev    Processes owner's tranche token redemption after the epoch has been executed on Centrifuge.
    ///         The trancheTokenAmount required to fulfill the redemption order was already locked in escrow
    ///         upon calling requestRedeem.
    function withdraw(address liquidityPool, uint256 currencyAmount, address receiver, address owner)
        public
        auth
        returns (uint256 trancheTokenAmount)
    {
        InvestmentState storage state = investments[liquidityPool][owner];
        _processRedeem(state, currencyAmount.toUint128(), liquidityPool, receiver, owner);
        trancheTokenAmount =
            uint256(_calculateTrancheTokenAmount(currencyAmount.toUint128(), liquidityPool, state.redeemPrice));
    }

    function _processRedeem(
        InvestmentState storage state,
        uint128 currencyAmount,
        address liquidityPool,
        address receiver,
        address owner
    ) internal {
        LiquidityPoolLike lPool = LiquidityPoolLike(liquidityPool);
        require(currencyAmount != 0, "InvestmentManager/currency-amount-is-zero");
        require(currencyAmount <= state.maxWithdraw, "InvestmentManager/exceeds-redeem-limits");
        state.maxWithdraw = state.maxWithdraw - currencyAmount;
        userEscrow.transferOut(lPool.asset(), owner, receiver, currencyAmount);
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
        currencyDecimals = ERC20Like(LiquidityPoolLike(liquidityPool).asset()).decimals();
        trancheTokenDecimals = ERC20Like(LiquidityPoolLike(liquidityPool).share()).decimals();
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
