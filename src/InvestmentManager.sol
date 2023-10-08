// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import {Auth} from "./util/Auth.sol";
import {MathLib} from "./util/MathLib.sol";
import {SafeTransferLib} from "./util/SafeTransferLib.sol";

interface GatewayLike {
    function increaseInvestOrder(uint64 poolId, bytes16 trancheId, address investor, uint128 currency, uint128 amount)
        external;
    function decreaseInvestOrder(uint64 poolId, bytes16 trancheId, address investor, uint128 currency, uint128 amount)
        external;
    function increaseRedeemOrder(uint64 poolId, bytes16 trancheId, address investor, uint128 currency, uint128 amount)
        external;
    function decreaseRedeemOrder(uint64 poolId, bytes16 trancheId, address investor, uint128 currency, uint128 amount)
        external;
    function collectInvest(uint64 poolId, bytes16 trancheId, address investor, uint128 currency) external;
    function collectRedeem(uint64 poolId, bytes16 trancheId, address investor, uint128 currency) external;
    function cancelInvestOrder(uint64 poolId, bytes16 trancheId, address investor, uint128 currency) external;
    function cancelRedeemOrder(uint64 poolId, bytes16 trancheId, address investor, uint128 currency) external;
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
    function poolId() external returns (uint64);
    function trancheId() external returns (bytes16);
    function asset() external view returns (address);
    function share() external view returns (address);
    function hasMember(address) external returns (bool);
    function updatePrice(uint256 price) external;
    function latestPrice() external view returns (uint128);
}

interface AuthTransferLike {
    function authTransferFrom(address from, address to, uint256 amount) external returns (bool);
}

interface PoolManagerLike {
    function currencyIdToAddress(uint128 currencyId) external view returns (address);
    function currencyAddressToId(address addr) external view returns (uint128);
    function getTrancheToken(uint64 poolId, bytes16 trancheId) external view returns (address);
    function getLiquidityPool(uint64 poolId, bytes16 trancheId, address currency) external view returns (address);
    function isAllowedAsInvestmentCurrency(uint64 poolId, address currencyAddress) external view returns (bool);
}

interface EscrowLike {
    function approve(address token, address spender, uint256 value) external;
}

interface UserEscrowLike {
    function transferIn(address token, address source, address destination, uint256 amount) external;
    function transferOut(address token, address owner, address destination, uint256 amount) external;
}

/// @dev Liquidity Pool orders and investment/redemption limits per user
struct LPValues {
    /// @dev Tranche tokens that can be claimed using `mint()`
    uint128 maxMint;
    /// @dev Weighted average price of deposits, used to convert maxMint to maxDeposit
    uint256 depositPrice;
    /// @dev Currency that can be claimed using `withdraw()`
    uint128 maxWithdraw;
    /// @dev Weighted average price of redemptions, used to convert maxWithdraw to maxRedeem
    uint256 redeemPrice;
    /// @dev Remaining invest (deposit) order in currency
    uint128 remainingInvestOrder;
    /// @dev Remaining redeem order in currency
    uint128 remainingRedeemOrder;
    ///@dev Flag whether this user has ever interacted with this liquidity pool
    bool exists;
}

/// @title  Investment Manager
/// @notice This is the main contract LiquidityPools interact with for
///         both incoming and outgoing investment transactions.
contract InvestmentManager is Auth {
    using MathLib for uint256;
    using MathLib for uint128;

    /// @dev Prices are fixed-point integers with 18 decimals
    uint8 internal constant PRICE_DECIMALS = 18;

    EscrowLike public immutable escrow;
    UserEscrowLike public immutable userEscrow;

    GatewayLike public gateway;
    PoolManagerLike public poolManager;

    mapping(address liquidityPool => mapping(address investor => LPValues)) public orderbook;

    // --- Events ---
    event File(bytes32 indexed what, address data);
    event ExecutedCollectInvest(
        uint64 indexed poolId,
        bytes16 indexed trancheId,
        address recipient,
        uint128 currency,
        uint128 currencyPayout,
        uint128 trancheTokensPayout
    );
    event ExecutedCollectRedeem(
        uint64 indexed poolId,
        bytes16 indexed trancheId,
        address recipient,
        uint128 currency,
        uint128 currencyPayout,
        uint128 trancheTokensPayout
    );
    event ExecutedDecreaseInvestOrder(
        uint64 indexed poolId, bytes16 indexed trancheId, address user, uint128 currency, uint128 currencyPayout
    );
    event ExecutedDecreaseRedeemOrder(
        uint64 indexed poolId, bytes16 indexed trancheId, address user, uint128 currency, uint128 trancheTokensPayout
    );
    event TriggerIncreaseRedeemOrder(
        uint64 indexed poolId, bytes16 indexed trancheId, address user, uint128 currency, uint128 trancheTokenAmount
    );
    event DepositCollect(address indexed owner);
    event RedeemCollect(address indexed owner);

    constructor(address escrow_, address userEscrow_) {
        escrow = EscrowLike(escrow_);
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
    /// @notice Request deposit. Liquidity pools have to request investments from Centrifuge before
    ///         tranche tokens can be minted. The deposit requests are added to the order book
    ///         on Centrifuge. Once the next epoch is executed on Centrifuge, liquidity pools can
    ///         proceed with tranche token payouts in case their orders got fulfilled.
    /// @dev    The user currency amount required to fulfill the deposit request have to be locked,
    ///         even though the tranche token payout can only happen after epoch execution.
    function requestDeposit(address liquidityPool, uint256 currencyAmount, address user) public auth {
        LiquidityPoolLike lPool = LiquidityPoolLike(liquidityPool);
        uint128 _currencyAmount = _toUint128(currencyAmount);
        require(_currencyAmount != 0, "InvestmentManager/zero-amount-not-allowed");

        uint64 poolId = lPool.poolId();
        address currency = lPool.asset();
        require(poolManager.isAllowedAsInvestmentCurrency(poolId, currency), "InvestmentManager/currency-not-allowed");
        require(
            _checkTransferRestriction(liquidityPool, address(0), user, convertToShares(liquidityPool, currencyAmount)),
            "InvestmentManager/transfer-not-allowed"
        );

        // Transfer the currency amount from user to escrow (lock currency in escrow)
        // Checks actual balance difference to support fee-on-transfer tokens
        uint256 preBalance = ERC20Like(currency).balanceOf(address(escrow));
        SafeTransferLib.safeTransferFrom(currency, user, address(escrow), _currencyAmount);
        uint256 postBalance = ERC20Like(currency).balanceOf(address(escrow));
        uint128 transferredAmount = _toUint128(postBalance - preBalance);

        LPValues storage lpValues = orderbook[liquidityPool][user];
        lpValues.remainingInvestOrder = lpValues.remainingInvestOrder + transferredAmount;
        lpValues.exists = true;

        gateway.increaseInvestOrder(
            poolId, lPool.trancheId(), user, poolManager.currencyAddressToId(currency), transferredAmount
        );
    }

    /// @notice Request tranche token redemption. Liquidity pools have to request redemptions
    ///         from Centrifuge before actual currency payouts can be done. The redemption
    ///         requests are added to the order book on Centrifuge. Once the next epoch is
    ///         executed on Centrifuge, liquidity pools can proceed with currency payouts
    ///         in case their orders got fulfilled.
    /// @dev    The user tranche tokens required to fulfill the redemption request have to be locked,
    ///         even though the currency payout can only happen after epoch execution.
    function requestRedeem(address liquidityPool, uint256 trancheTokenAmount, address user) public auth {
        uint128 _trancheTokenAmount = _toUint128(trancheTokenAmount);
        require(_trancheTokenAmount != 0, "InvestmentManager/zero-amount-not-allowed");
        LiquidityPoolLike lPool = LiquidityPoolLike(liquidityPool);

        // You cannot redeem using a disallowed investment currency, instead another LP will have to be used
        require(
            poolManager.isAllowedAsInvestmentCurrency(lPool.poolId(), lPool.asset()),
            "InvestmentManager/currency-not-allowed"
        );

        _processIncreaseRedeemRequest(liquidityPool, _trancheTokenAmount, user);
    }

    function _processIncreaseRedeemRequest(address liquidityPool, uint128 trancheTokenAmount, address user) internal {
        LiquidityPoolLike lPool = LiquidityPoolLike(liquidityPool);
        LPValues storage lpValues = orderbook[liquidityPool][user];
        lpValues.remainingRedeemOrder = lpValues.remainingRedeemOrder + trancheTokenAmount;

        // Transfer the tranche token amount from user to escrow (lock tranche tokens in escrow)
        require(
            AuthTransferLike(address(lPool.share())).authTransferFrom(user, address(escrow), trancheTokenAmount),
            "InvestmentManager/transfer-failed"
        );

        gateway.increaseRedeemOrder(
            lPool.poolId(), lPool.trancheId(), user, poolManager.currencyAddressToId(lPool.asset()), trancheTokenAmount
        );
    }

    function decreaseDepositRequest(address liquidityPool, uint256 _currencyAmount, address user) public auth {
        uint128 currencyAmount = _toUint128(_currencyAmount);
        LiquidityPoolLike _liquidityPool = LiquidityPoolLike(liquidityPool);
        gateway.decreaseInvestOrder(
            _liquidityPool.poolId(),
            _liquidityPool.trancheId(),
            user,
            poolManager.currencyAddressToId(_liquidityPool.asset()),
            currencyAmount
        );
    }

    function decreaseRedeemRequest(address liquidityPool, uint256 _trancheTokenAmount, address user) public auth {
        uint128 trancheTokenAmount = _toUint128(_trancheTokenAmount);
        LiquidityPoolLike _liquidityPool = LiquidityPoolLike(liquidityPool);
        require(
            _checkTransferRestriction(liquidityPool, address(0), user, _trancheTokenAmount),
            "InvestmentManager/transfer-not-allowed"
        );
        gateway.decreaseRedeemOrder(
            _liquidityPool.poolId(),
            _liquidityPool.trancheId(),
            user,
            poolManager.currencyAddressToId(_liquidityPool.asset()),
            trancheTokenAmount
        );
    }

    function cancelDepositRequest(address liquidityPool, address user) public auth {
        LiquidityPoolLike _liquidityPool = LiquidityPoolLike(liquidityPool);
        gateway.cancelInvestOrder(
            _liquidityPool.poolId(),
            _liquidityPool.trancheId(),
            user,
            poolManager.currencyAddressToId(_liquidityPool.asset())
        );
    }

    function cancelRedeemRequest(address liquidityPool, address user) public auth {
        LiquidityPoolLike _liquidityPool = LiquidityPoolLike(liquidityPool);
        uint256 approximateTrancheTokensPayout = userRedeemRequest(liquidityPool, user);
        require(
            _checkTransferRestriction(liquidityPool, address(0), user, approximateTrancheTokensPayout),
            "InvestmentManager/transfer-not-allowed"
        );
        gateway.cancelRedeemOrder(
            _liquidityPool.poolId(),
            _liquidityPool.trancheId(),
            user,
            poolManager.currencyAddressToId(_liquidityPool.asset())
        );
    }

    // --- Incoming message handling ---
    /// @notice Update the price of a tranche token
    /// @dev    This also happens automatically on incoming order executions,
    ///         but this incoming call from Centrifuge can be used to update the price
    ///         whenever the price is outdated but no orders are outstanding.
    function updateTrancheTokenPrice(uint64 poolId, bytes16 trancheId, uint128 currencyId, uint128 price)
        public
        onlyGateway
    {
        address currency = poolManager.currencyIdToAddress(currencyId);
        address liquidityPool = poolManager.getLiquidityPool(poolId, trancheId, currency);
        LiquidityPoolLike(liquidityPool).updatePrice(price);
    }

    function handleExecutedCollectInvest(
        uint64 poolId,
        bytes16 trancheId,
        address recipient,
        uint128 currency,
        uint128 currencyPayout,
        uint128 trancheTokensPayout,
        uint128 remainingInvestOrder
    ) public onlyGateway {
        address liquidityPool =
            poolManager.getLiquidityPool(poolId, trancheId, poolManager.currencyIdToAddress(currency));

        LPValues storage lpValues = orderbook[liquidityPool][recipient];
        lpValues.depositPrice = _calculatePrice(
            liquidityPool,
            _maxDeposit(liquidityPool, recipient) + currencyPayout,
            lpValues.maxMint + trancheTokensPayout
        );
        lpValues.maxMint = lpValues.maxMint + trancheTokensPayout;
        lpValues.remainingInvestOrder = remainingInvestOrder;

        LiquidityPoolLike(liquidityPool).updatePrice(
            _calculatePrice(liquidityPool, currencyPayout, trancheTokensPayout)
        );

        // Mint to escrow. Recipient can claim by calling withdraw / redeem
        ERC20Like trancheToken = ERC20Like(LiquidityPoolLike(liquidityPool).share());
        trancheToken.mint(address(escrow), trancheTokensPayout);

        emit ExecutedCollectInvest(poolId, trancheId, recipient, currency, currencyPayout, trancheTokensPayout);
    }

    function handleExecutedCollectRedeem(
        uint64 poolId,
        bytes16 trancheId,
        address recipient,
        uint128 currency,
        uint128 currencyPayout,
        uint128 trancheTokensPayout,
        uint128 remainingRedeemOrder
    ) public onlyGateway {
        address _currency = poolManager.currencyIdToAddress(currency);
        address liquidityPool = poolManager.getLiquidityPool(poolId, trancheId, _currency);

        LPValues storage lpValues = orderbook[liquidityPool][recipient];
        require(lpValues.exists == true, "InvestmentManager/non-existent-recipient");

        // Calculate new weighted average redeem price and update order book values
        lpValues.redeemPrice = _calculatePrice(
            liquidityPool,
            lpValues.maxWithdraw + currencyPayout,
            _toUint128(maxRedeem(liquidityPool, recipient)) + trancheTokensPayout
        );
        lpValues.maxWithdraw = lpValues.maxWithdraw + currencyPayout;
        lpValues.remainingRedeemOrder = remainingRedeemOrder;

        LiquidityPoolLike(liquidityPool).updatePrice(
            _calculatePrice(liquidityPool, currencyPayout, trancheTokensPayout)
        );

        // Transfer currency to user escrow to claim on withdraw/redeem,
        // and burn redeemed tranche tokens from escrow
        userEscrow.transferIn(_currency, address(escrow), recipient, currencyPayout);
        ERC20Like trancheToken = ERC20Like(LiquidityPoolLike(liquidityPool).share());
        trancheToken.burn(address(escrow), trancheTokensPayout);

        emit ExecutedCollectRedeem(poolId, trancheId, recipient, currency, currencyPayout, trancheTokensPayout);
    }

    function handleExecutedDecreaseInvestOrder(
        uint64 poolId,
        bytes16 trancheId,
        address user,
        uint128 currency,
        uint128 currencyPayout,
        uint128 remainingInvestOrder
    ) public onlyGateway {
        address _currency = poolManager.currencyIdToAddress(currency);
        address liquidityPool = poolManager.getLiquidityPool(poolId, trancheId, _currency);

        LPValues storage lpValues = orderbook[liquidityPool][user];
        require(lpValues.exists == true, "InvestmentManager/non-existent-recipient");

        // Calculating the price with both payouts as currencyPayout
        // leads to an effective redeem price of 1.0 and thus the user actually receiving
        // exactly currencyPayout on both deposit() and mint()
        lpValues.redeemPrice = _calculatePrice(
            liquidityPool,
            lpValues.maxWithdraw + currencyPayout,
            _toUint128(maxRedeem(liquidityPool, user)) + currencyPayout
        );
        lpValues.maxWithdraw = lpValues.maxWithdraw + currencyPayout;
        lpValues.remainingInvestOrder = remainingInvestOrder;

        // Transfer currency amount to userEscrow
        userEscrow.transferIn(_currency, address(escrow), user, currencyPayout);

        emit ExecutedDecreaseInvestOrder(poolId, trancheId, user, currency, currencyPayout);
    }

    /// @dev Compared to handleExecutedDecreaseInvestOrder, there is no
    ///      transfer of currency in this function because they
    ///      can stay in the Escrow, ready to be claimed on deposit/mint.
    function handleExecutedDecreaseRedeemOrder(
        uint64 poolId,
        bytes16 trancheId,
        address user,
        uint128 currency,
        uint128 trancheTokensPayout,
        uint128 remainingRedeemOrder
    ) public onlyGateway {
        address liquidityPool =
            poolManager.getLiquidityPool(poolId, trancheId, poolManager.currencyIdToAddress(currency));

        // Calculating the price with both payouts as trancheTokensPayout
        // leads to an effective redeem price of 1.0 and thus the user actually receiving
        // exactly trancheTokensPayout on both deposit() and mint()
        LPValues storage lpValues = orderbook[liquidityPool][user];
        lpValues.depositPrice = _calculatePrice(
            liquidityPool,
            _maxDeposit(liquidityPool, user) + trancheTokensPayout,
            lpValues.maxMint + trancheTokensPayout
        );
        lpValues.maxMint = lpValues.maxMint + trancheTokensPayout;
        lpValues.remainingRedeemOrder = remainingRedeemOrder;

        emit ExecutedDecreaseRedeemOrder(poolId, trancheId, user, currency, trancheTokensPayout);
    }

    function handleTriggerIncreaseRedeemOrder(
        uint64 poolId,
        bytes16 trancheId,
        address user,
        uint128 currency,
        uint128 trancheTokenAmount
    ) public onlyGateway {
        address _currency = poolManager.currencyIdToAddress(currency);
        address liquidityPool = poolManager.getLiquidityPool(poolId, trancheId, _currency);
        _processIncreaseRedeemRequest(liquidityPool, trancheTokenAmount, user);
        emit TriggerIncreaseRedeemOrder(poolId, trancheId, user, currency, trancheTokenAmount);
    }

    // --- View functions ---
    function convertToShares(address liquidityPool, uint256 _assets) public view returns (uint256 shares) {
        uint128 latestPrice = LiquidityPoolLike(liquidityPool).latestPrice();
        shares = uint256(_calculateTrancheTokenAmount(_toUint128(_assets), liquidityPool, latestPrice));
    }

    function convertToAssets(address liquidityPool, uint256 _shares) public view returns (uint256 assets) {
        uint128 latestPrice = LiquidityPoolLike(liquidityPool).latestPrice();
        assets = uint256(_calculateCurrencyAmount(_toUint128(_shares), liquidityPool, latestPrice));
    }

    function maxDeposit(address liquidityPool, address user) public view returns (uint256) {
        if (!_checkTransferRestriction(liquidityPool, address(escrow), user, 0)) return 0;
        return uint256(_maxDeposit(liquidityPool, user));
    }

    function _maxDeposit(address liquidityPool, address user) internal view returns (uint128) {
        LPValues memory lpValues = orderbook[liquidityPool][user];
        return _calculateCurrencyAmount(lpValues.maxMint, liquidityPool, lpValues.depositPrice);
    }

    function maxMint(address liquidityPool, address user) public view returns (uint256 trancheTokenAmount) {
        if (!_checkTransferRestriction(liquidityPool, address(escrow), user, 0)) return 0;
        return uint256(orderbook[liquidityPool][user].maxMint);
    }

    function maxWithdraw(address liquidityPool, address user) public view returns (uint256 currencyAmount) {
        return uint256(orderbook[liquidityPool][user].maxWithdraw);
    }

    function maxRedeem(address liquidityPool, address user) public view returns (uint256 trancheTokenAmount) {
        LPValues memory lpValues = orderbook[liquidityPool][user];
        return uint256(_calculateTrancheTokenAmount(lpValues.maxWithdraw, liquidityPool, lpValues.redeemPrice));
    }

    function previewDeposit(address liquidityPool, address user, uint256 _currencyAmount)
        public
        view
        returns (uint256 trancheTokenAmount)
    {
        uint128 currencyAmount = _toUint128(_currencyAmount);
        LPValues memory lpValues = orderbook[liquidityPool][user];
        trancheTokenAmount = uint256(_calculateTrancheTokenAmount(currencyAmount, liquidityPool, lpValues.depositPrice));
    }

    function previewMint(address liquidityPool, address user, uint256 _trancheTokenAmount)
        public
        view
        returns (uint256 currencyAmount)
    {
        uint128 trancheTokenAmount = _toUint128(_trancheTokenAmount);
        LPValues memory lpValues = orderbook[liquidityPool][user];
        currencyAmount = uint256(_calculateCurrencyAmount(trancheTokenAmount, liquidityPool, lpValues.depositPrice));
    }

    function previewWithdraw(address liquidityPool, address user, uint256 _currencyAmount)
        public
        view
        returns (uint256 trancheTokenAmount)
    {
        uint128 currencyAmount = _toUint128(_currencyAmount);
        LPValues memory lpValues = orderbook[liquidityPool][user];
        trancheTokenAmount = uint256(_calculateTrancheTokenAmount(currencyAmount, liquidityPool, lpValues.redeemPrice));
    }

    function previewRedeem(address liquidityPool, address user, uint256 _trancheTokenAmount)
        public
        view
        returns (uint256 currencyAmount)
    {
        uint128 trancheTokenAmount = _toUint128(_trancheTokenAmount);
        LPValues memory lpValues = orderbook[liquidityPool][user];
        currencyAmount = uint256(_calculateCurrencyAmount(trancheTokenAmount, liquidityPool, lpValues.redeemPrice));
    }

    function userDepositRequest(address liquidityPool, address user) public view returns (uint256 currencyAmount) {
        currencyAmount = uint256(orderbook[liquidityPool][user].remainingInvestOrder);
    }

    function userRedeemRequest(address liquidityPool, address user) public view returns (uint256 trancheTokenAmount) {
        trancheTokenAmount = uint256(orderbook[liquidityPool][user].remainingRedeemOrder);
    }

    // --- Liquidity Pool processing functions ---
    /// @notice Processes owner's currency deposit / investment after the epoch has been executed on Centrifuge.
    ///         The currency required to fulfill the invest order is already locked in escrow upon calling
    /// requestDeposit.
    function deposit(address liquidityPool, uint256 currencyAmount, address receiver, address owner)
        public
        auth
        returns (uint256 trancheTokenAmount)
    {
        trancheTokenAmount = previewDeposit(liquidityPool, owner, currencyAmount);
        _processDeposit(orderbook[liquidityPool][owner], _toUint128(trancheTokenAmount), liquidityPool, receiver);
    }

    /// @notice Processes owner's currency deposit / investment after the epoch has been executed on Centrifuge.
    ///         The currency required to fulfill the invest order is already locked in escrow upon calling
    /// requestDeposit.
    function mint(address liquidityPool, uint256 trancheTokenAmount, address receiver, address owner)
        public
        auth
        returns (uint256 currencyAmount)
    {
        currencyAmount = previewMint(liquidityPool, owner, trancheTokenAmount);
        _processDeposit(orderbook[liquidityPool][owner], _toUint128(trancheTokenAmount), liquidityPool, receiver);
    }

    function _processDeposit(
        LPValues storage lpValues,
        uint128 trancheTokenAmount,
        address liquidityPool,
        address receiver
    ) internal {
        LiquidityPoolLike lPool = LiquidityPoolLike(liquidityPool);
        require(trancheTokenAmount != 0, "InvestmentManager/tranche-token-amount-is-zero");
        require(trancheTokenAmount <= lpValues.maxMint, "InvestmentManager/exceeds-deposit-limits");
        lpValues.maxMint = lpValues.maxMint - trancheTokenAmount;
        require(
            lPool.transferFrom(address(escrow), receiver, trancheTokenAmount),
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
        currencyAmount = previewRedeem(liquidityPool, owner, trancheTokenAmount);
        _processRedeem(orderbook[liquidityPool][owner], _toUint128(currencyAmount), liquidityPool, receiver, owner);
    }

    /// @dev    Processes owner's tranche token redemption after the epoch has been executed on Centrifuge.
    ///         The trancheTokenAmount required to fulfill the redemption order was already locked in escrow
    ///         upon calling requestRedeem.
    ///         the currencyAmount payout/withdrawal.
    function withdraw(address liquidityPool, uint256 currencyAmount, address receiver, address owner)
        public
        auth
        returns (uint256 trancheTokenAmount)
    {
        trancheTokenAmount = previewWithdraw(liquidityPool, owner, currencyAmount);
        _processRedeem(orderbook[liquidityPool][owner], _toUint128(currencyAmount), liquidityPool, receiver, owner);
    }

    function _processRedeem(
        LPValues storage lpValues,
        uint128 currencyAmount,
        address liquidityPool,
        address receiver,
        address owner
    ) internal {
        LiquidityPoolLike lPool = LiquidityPoolLike(liquidityPool);
        require(currencyAmount != 0, "InvestmentManager/currency-amount-is-zero");
        require(currencyAmount <= lpValues.maxWithdraw, "InvestmentManager/exceeds-redeem-limits");
        lpValues.maxWithdraw = lpValues.maxWithdraw - currencyAmount;
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
        public
        view
        returns (uint256 price)
    {
        if (trancheTokenAmount == 0) {
            return 0;
        }

        (uint8 currencyDecimals, uint8 trancheTokenDecimals) = _getPoolDecimals(liquidityPool);

        uint256 currencyAmountInPriceDecimals = _toPriceDecimals(currencyAmount, currencyDecimals);
        uint256 trancheTokenAmountInPriceDecimals = _toPriceDecimals(trancheTokenAmount, trancheTokenDecimals);

        price = currencyAmountInPriceDecimals.mulDiv(
            10 ** PRICE_DECIMALS, trancheTokenAmountInPriceDecimals, MathLib.Rounding.Down
        );
    }

    /// @dev    Safe type conversion from uint256 to uint128.
    function _toUint128(uint256 _value) internal pure returns (uint128 value) {
        if (_value > type(uint128).max) {
            revert("InvestmentManager/uint128-overflow");
        } else {
            value = uint128(_value);
        }
    }

    /// @dev    When converting currency to tranche token amounts using the price,
    ///         all values are normalized to PRICE_DECIMALS
    function _toPriceDecimals(uint128 _value, uint8 decimals) internal pure returns (uint256 value) {
        if (PRICE_DECIMALS == decimals) return uint256(_value);
        value = uint256(_value) * 10 ** (PRICE_DECIMALS - decimals);
    }

    /// @dev    Convert decimals of the value from the price decimals back to the intended decimals
    function _fromPriceDecimals(uint256 _value, uint8 decimals) internal pure returns (uint128 value) {
        if (PRICE_DECIMALS == decimals) return _toUint128(_value);
        value = _toUint128(_value / 10 ** (PRICE_DECIMALS - decimals));
    }

    /// @dev    Return the currency decimals and the tranche token decimals for a given liquidityPool
    function _getPoolDecimals(address liquidityPool)
        internal
        view
        returns (uint8 currencyDecimals, uint8 trancheTokenDecimals)
    {
        currencyDecimals = ERC20Like(LiquidityPoolLike(liquidityPool).asset()).decimals();
        trancheTokenDecimals = LiquidityPoolLike(liquidityPool).decimals();
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
