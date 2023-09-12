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
    function decimals() external view returns (uint8);
    function mint(address, uint256) external;
    function burn(address, uint256) external;
}

interface LiquidityPoolLike is ERC20Like {
    function poolId() external returns (uint64);
    function trancheId() external returns (bytes16);
    function asset() external view returns (address);
    function hasMember(address) external returns (bool);
    function updatePrice(uint128 price) external;
    function checkTransferRestriction(address from, address to, uint256 value) external view returns (bool);
    function latestPrice() external view returns (uint128);
}

interface PoolManagerLike {
    function currencyIdToAddress(uint128 currencyId) external view returns (address);
    function currencyAddressToId(address addr) external view returns (uint128);
    function getTrancheToken(uint64 poolId, bytes16 trancheId) external view returns (address);
    function getLiquidityPool(uint64 poolId, bytes16 trancheId, address currency) external view returns (address);
    function isAllowedAsPoolCurrency(uint64 poolId, address currencyAddress) external view returns (bool);
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
    uint128 maxDeposit; // denominated in currency
    uint128 maxMint; // denominated in tranche tokens
    uint128 maxWithdraw; // denominated in currency
    uint128 maxRedeem; // denominated in tranche tokens
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

    mapping(address investor => mapping(address liquidityPool => LPValues)) public orderbook;

    // --- Events ---
    event File(bytes32 indexed what, address data);
    event ProcessDeposit(
        address indexed liquidityPool, address indexed user, uint128 currencyAmount, uint128 trancheTokenAmount
    );
    event ProcessRedeem(
        address indexed liquidityPool, address indexed user, uint128 currencyAmount, uint128 trancheTokenAmount
    );
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
    /// @notice Request deposit. Liquidity pools have to request investments from Centrifuge before actual tranche tokens can be minted.
    ///         The deposit requests are added to the order book on Centrifuge. Once the next epoch is executed on Centrifuge,
    ///         liquidity pools can proceed with tranche token payouts in case their orders got fulfilled.
    ///         If an amount of 0 is passed, this triggers cancelling outstanding deposit orders.
    /// @dev    The user currency amount required to fulfill the deposit request have to be locked,
    ///         even though the tranche token payout can only happen after epoch execution.
    function requestDeposit(address liquidityPool, uint256 currencyAmount, address user) public auth {
        LiquidityPoolLike lPool = LiquidityPoolLike(liquidityPool);
        uint128 _currencyAmount = _toUint128(currencyAmount);
        require(_currencyAmount != 0, "InvestmentManager/zero-amount-not-allowed");

        uint64 poolId = lPool.poolId();
        bytes16 trancheId = lPool.trancheId();
        address currency = lPool.asset();
        uint128 currencyId = poolManager.currencyAddressToId(currency);

        poolManager.isAllowedAsPoolCurrency(poolId, currency);
        require(
            lPool.checkTransferRestriction(address(0), user, convertToShares(liquidityPool, currencyAmount)),
            "InvestmentManager/transfer-not-allowed"
        );

        // Transfer the currency amount from user to escrow (lock currency in escrow)
        SafeTransferLib.safeTransferFrom(currency, user, address(escrow), _currencyAmount);

        gateway.increaseInvestOrder(poolId, trancheId, user, currencyId, _currencyAmount);
    }

    /// @notice Request tranche token redemption. Liquidity pools have to request redemptions from Centrifuge before actual currency payouts can be done.
    ///         The redemption requests are added to the order book on Centrifuge. Once the next epoch is executed on Centrifuge,
    ///         liquidity pools can proceed with currency payouts in case their orders got fulfilled.
    ///         If an amount of 0 is passed, this triggers cancelling outstanding redemption orders.
    /// @dev    The user tranche tokens required to fulfill the redemption request have to be locked, even though the currency payout can only happen after epoch execution.
    function requestRedeem(address liquidityPool, uint256 trancheTokenAmount, address user) public auth {
        LiquidityPoolLike lPool = LiquidityPoolLike(liquidityPool);
        uint128 _trancheTokenAmount = _toUint128(trancheTokenAmount);
        require(_trancheTokenAmount != 0, "InvestmentManager/zero-amount-not-allowed");

        uint64 poolId = lPool.poolId();
        bytes16 trancheId = lPool.trancheId();
        address currency = lPool.asset();
        uint128 currencyId = poolManager.currencyAddressToId(currency);

        poolManager.isAllowedAsPoolCurrency(poolId, currency);

        // Transfer the tranche token amount from user to escrow (lock tranche tokens in escrow)
        lPool.transferFrom(user, address(escrow), _trancheTokenAmount);

        gateway.increaseRedeemOrder(poolId, trancheId, user, currencyId, _trancheTokenAmount);
    }

    function decreaseDepositRequest(address liquidityPool, uint256 _currencyAmount, address user) public auth {
        uint128 currencyAmount = _toUint128(_currencyAmount);
        LiquidityPoolLike _liquidityPool = LiquidityPoolLike(msg.sender);
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
        LiquidityPoolLike _liquidityPool = LiquidityPoolLike(msg.sender);
        require(
            _liquidityPool.checkTransferRestriction(address(0), user, _trancheTokenAmount),
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
        LiquidityPoolLike _liquidityPool = LiquidityPoolLike(msg.sender);
        gateway.cancelInvestOrder(
            _liquidityPool.poolId(),
            _liquidityPool.trancheId(),
            user,
            poolManager.currencyAddressToId(_liquidityPool.asset())
        );
    }

    function cancelRedeemRequest(address liquidityPool, address user) public auth {
        LiquidityPoolLike _liquidityPool = LiquidityPoolLike(msg.sender);
        // TODO: last argument should be replaced by remaining redeem order
        require(
            _liquidityPool.checkTransferRestriction(address(0), user, type(uint128).max),
            "InvestmentManager/transfer-not-allowed"
        );
        gateway.cancelRedeemOrder(
            _liquidityPool.poolId(),
            _liquidityPool.trancheId(),
            user,
            poolManager.currencyAddressToId(_liquidityPool.asset())
        );
    }

    function collectDeposit(address liquidityPool, address user) public auth {
        LiquidityPoolLike _liquidityPool = LiquidityPoolLike(msg.sender);
        // TODO: last argument should be replaced by remaining invest order
        require(
            _liquidityPool.checkTransferRestriction(address(escrow), user, type(uint128).max),
            "InvestmentManager/transfer-not-allowed"
        );
        gateway.collectInvest(
            _liquidityPool.poolId(),
            _liquidityPool.trancheId(),
            user,
            poolManager.currencyAddressToId(_liquidityPool.asset())
        );
    }

    function collectRedeem(address liquidityPool, address user) public auth {
        LiquidityPoolLike _liquidityPool = LiquidityPoolLike(msg.sender);
        gateway.collectRedeem(
            _liquidityPool.poolId(),
            _liquidityPool.trancheId(),
            user,
            poolManager.currencyAddressToId(_liquidityPool.asset())
        );
    }

    // --- Incoming message handling ---
    function updateTrancheTokenPrice(uint64 poolId, bytes16 trancheId, uint128 currencyId, uint128 price)
        public
        onlyGateway
    {
        address currency = poolManager.currencyIdToAddress(currencyId);
        address liquidityPool = poolManager.getLiquidityPool(poolId, trancheId, currency);
        require(liquidityPool != address(0), "InvestmentManager/tranche-does-not-exist");

        LiquidityPoolLike(liquidityPool).updatePrice(price);
    }

    function handleExecutedCollectInvest(
        uint64 poolId,
        bytes16 trancheId,
        address recipient,
        uint128 currency,
        uint128 currencyPayout,
        uint128 trancheTokensPayout
    ) public onlyGateway {
        require(currencyPayout != 0, "InvestmentManager/zero-invest");
        address _currency = poolManager.currencyIdToAddress(currency);
        address liquidityPool = poolManager.getLiquidityPool(poolId, trancheId, _currency);
        require(liquidityPool != address(0), "InvestmentManager/tranche-does-not-exist");

        LPValues storage lpValues = orderbook[recipient][liquidityPool];
        lpValues.maxDeposit = lpValues.maxDeposit + currencyPayout;
        lpValues.maxMint = lpValues.maxMint + trancheTokensPayout;

        LiquidityPoolLike(liquidityPool).mint(address(escrow), trancheTokensPayout); // mint to escrow. Recipient can claim by calling withdraw / redeem
        _updateLiquidityPoolPrice(liquidityPool, currencyPayout, trancheTokensPayout);

        emit ExecutedCollectInvest(poolId, trancheId, recipient, currency, currencyPayout, trancheTokensPayout);
    }

    function handleExecutedCollectRedeem(
        uint64 poolId,
        bytes16 trancheId,
        address recipient,
        uint128 currency,
        uint128 currencyPayout,
        uint128 trancheTokensPayout
    ) public onlyGateway {
        require(trancheTokensPayout != 0, "InvestmentManager/zero-redeem");
        address _currency = poolManager.currencyIdToAddress(currency);
        address liquidityPool = poolManager.getLiquidityPool(poolId, trancheId, _currency);
        require(liquidityPool != address(0), "InvestmentManager/tranche-does-not-exist");

        LPValues storage lpValues = orderbook[recipient][liquidityPool];
        lpValues.maxWithdraw = lpValues.maxWithdraw + currencyPayout;
        lpValues.maxRedeem = lpValues.maxRedeem + trancheTokensPayout;

        userEscrow.transferIn(_currency, address(escrow), recipient, currencyPayout);
        LiquidityPoolLike(liquidityPool).burn(address(escrow), trancheTokensPayout); // burned redeemed tokens from escrow
        _updateLiquidityPoolPrice(liquidityPool, currencyPayout, trancheTokensPayout);

        emit ExecutedCollectRedeem(poolId, trancheId, recipient, currency, currencyPayout, trancheTokensPayout);
    }

    function handleExecutedDecreaseInvestOrder(
        uint64 poolId,
        bytes16 trancheId,
        address user,
        uint128 currency,
        uint128 currencyPayout
    ) public onlyGateway {
        require(currencyPayout != 0, "InvestmentManager/zero-payout");

        address _currency = poolManager.currencyIdToAddress(currency);
        address liquidityPool = poolManager.getLiquidityPool(poolId, trancheId, _currency);
        require(liquidityPool != address(0), "InvestmentManager/tranche-does-not-exist");
        require(_currency == LiquidityPoolLike(liquidityPool).asset(), "InvestmentManager/not-tranche-currency");

        // transfer to user escrow
        userEscrow.transferIn(_currency, address(escrow), user, currencyPayout);
        LPValues storage lpValues = orderbook[user][liquidityPool];
        lpValues.maxRedeem = lpValues.maxRedeem + currencyPayout;
        lpValues.maxWithdraw = lpValues.maxWithdraw + currencyPayout;

        emit ExecutedDecreaseInvestOrder(poolId, trancheId, user, currency, currencyPayout);
    }

    function handleExecutedDecreaseRedeemOrder(
        uint64 poolId,
        bytes16 trancheId,
        address user,
        uint128 currency,
        uint128 trancheTokenPayout
    ) public onlyGateway {
        require(trancheTokenPayout != 0, "InvestmentManager/zero-payout");

        address _currency = poolManager.currencyIdToAddress(currency);
        address liquidityPool = poolManager.getLiquidityPool(poolId, trancheId, _currency);
        require(address(liquidityPool) != address(0), "InvestmentManager/tranche-does-not-exist");

        // transfer to user escrow
        LPValues storage lpValues = orderbook[user][liquidityPool];
        lpValues.maxDeposit= lpValues.maxDeposit + trancheTokenPayout;
        lpValues.maxMint = lpValues.maxMint + trancheTokenPayout;
    
        emit ExecutedDecreaseRedeemOrder(poolId, trancheId, user, currency, trancheTokenPayout);
    }

    // --- View functions ---
    function totalAssets(address liquidityPool, uint256 totalSupply) public view returns (uint256 _totalAssets) {
        _totalAssets = convertToAssets(liquidityPool, totalSupply);
    }

    /// @dev Calculates the amount of shares / tranche tokens that any user would get for the amount of currency / assets provided.
    ///      The calculation is based on the tranche token price from the most recent epoch retrieved from Centrifuge.
    function convertToShares(address liquidityPool, uint256 _assets) public view auth returns (uint256 shares) {
        uint128 latestPrice = LiquidityPoolLike(liquidityPool).latestPrice();
        if (latestPrice == 0) {
            // If the price is not set, we assume it is 1.00
            latestPrice = uint128(1 * 10 ** PRICE_DECIMALS);
        }

        (uint8 currencyDecimals, uint8 trancheTokenDecimals) = _getPoolDecimals(liquidityPool);
        uint128 assets = _toUint128(_assets);

        shares = assets.mulDiv(
            10 ** (PRICE_DECIMALS + trancheTokenDecimals - currencyDecimals), latestPrice, MathLib.Rounding.Down
        );
    }

    /// @dev Calculates the asset value for an amount of shares / tranche tokens provided.
    ///      The calculation is based on the tranche token price from the most recent epoch retrieved from Centrifuge.
    function convertToAssets(address liquidityPool, uint256 _shares) public view auth returns (uint256 assets) {
        uint128 latestPrice = LiquidityPoolLike(liquidityPool).latestPrice();
        if (latestPrice == 0) {
            // If the price is not set, we assume it is 1.00
            latestPrice = uint128(1 * 10 ** PRICE_DECIMALS);
        }

        (uint8 currencyDecimals, uint8 trancheTokenDecimals) = _getPoolDecimals(liquidityPool);
        uint128 shares = _toUint128(_shares);

        assets = shares.mulDiv(
            latestPrice, 10 ** (PRICE_DECIMALS + trancheTokenDecimals - currencyDecimals), MathLib.Rounding.Down
        );
    }

    /// @return currencyAmount is type of uint256 to support the EIP4626 Liquidity Pool interface
    function maxDeposit(address liquidityPool, address user) public view returns (uint256 currencyAmount) {
        currencyAmount = uint256(orderbook[user][liquidityPool].maxDeposit);
    }

    /// @return trancheTokenAmount type of uint256 to support the EIP4626 Liquidity Pool interface
    function maxMint(address liquidityPool, address user) public view returns (uint256 trancheTokenAmount) {
        trancheTokenAmount = uint256(orderbook[user][liquidityPool].maxMint);
    }

    /// @return currencyAmount type of uint256 to support the EIP4626 Liquidity Pool interface
    function maxWithdraw(address liquidityPool, address user) public view returns (uint256 currencyAmount) {
        currencyAmount = uint256(orderbook[user][liquidityPool].maxWithdraw);
    }

    /// @return trancheTokenAmount type of uint256 to support the EIP4626 Liquidity Pool interface
    function maxRedeem(address liquidityPool, address user) public view returns (uint256 trancheTokenAmount) {
        trancheTokenAmount = uint256(orderbook[user][liquidityPool].maxRedeem);
    }

    /// @return trancheTokenAmount is type of uint256 to support the EIP4626 Liquidity Pool interface
    function previewDeposit(address liquidityPool, address user, uint256 _currencyAmount)
        public
        view
        returns (uint256 trancheTokenAmount)
    {
        uint128 currencyAmount = _toUint128(_currencyAmount);
        uint256 depositPrice = calculateDepositPrice(user, liquidityPool);
        if (depositPrice == 0) return 0;

        trancheTokenAmount = uint256(_calculateTrancheTokenAmount(currencyAmount, liquidityPool, depositPrice));
    }

    /// @return currencyAmount is type of uint256 to support the EIP4626 Liquidity Pool interface
    function previewMint(address liquidityPool, address user, uint256 _trancheTokenAmount)
        public
        view
        returns (uint256 currencyAmount)
    {
        uint128 trancheTokenAmount = _toUint128(_trancheTokenAmount);
        uint256 depositPrice = calculateDepositPrice(user, liquidityPool);
        if (depositPrice == 0) return 0;

        currencyAmount = uint256(_calculateCurrencyAmount(trancheTokenAmount, liquidityPool, depositPrice));
    }

    /// @return trancheTokenAmount is type of uint256 to support the EIP4626 Liquidity Pool interface
    function previewWithdraw(address liquidityPool, address user, uint256 _currencyAmount)
        public
        view
        returns (uint256 trancheTokenAmount)
    {
        uint128 currencyAmount = _toUint128(_currencyAmount);
        uint256 redeemPrice = calculateRedeemPrice(user, liquidityPool);
        if (redeemPrice == 0) return 0;

        trancheTokenAmount = uint256(_calculateTrancheTokenAmount(currencyAmount, liquidityPool, redeemPrice));
    }

    /// @return currencyAmount is type of uint256 to support the EIP4626 Liquidity Pool interface
    function previewRedeem(address liquidityPool, address user, uint256 _trancheTokenAmount)
        public
        view
        returns (uint256 currencyAmount)
    {
        uint128 trancheTokenAmount = _toUint128(_trancheTokenAmount);
        uint256 redeemPrice = calculateRedeemPrice(user, liquidityPool);
        if (redeemPrice == 0) return 0;

        currencyAmount = uint256(_calculateCurrencyAmount(trancheTokenAmount, liquidityPool, redeemPrice));
    }

    // --- Liquidity Pool processing functions ---
    /// @notice Processes owner's currency deposit / investment after the epoch has been executed on Centrifuge.
    ///         In case owner's invest order was fulfilled (partially or in full) on Centrifuge during epoch execution MaxDeposit and MaxMint are increased and tranche tokens can be transferred to user's wallet on calling processDeposit.
    ///         Note: The currency required to fulfill the invest order is already locked in escrow upon calling requestDeposit.
    /// @dev    trancheTokenAmount return value is type of uint256 to be compliant with EIP4626 LiquidityPool interface
    /// @return trancheTokenAmount the amount of tranche tokens transferred to the user's wallet after successful deposit.
    function processDeposit(address liquidityPool, uint256 currencyAmount, address receiver, address owner)
        public
        auth
        returns (uint256 trancheTokenAmount)
    {
        uint128 _currencyAmount = _toUint128(currencyAmount);
        require(
            (_currencyAmount <= orderbook[owner][liquidityPool].maxDeposit && _currencyAmount != 0),
            "InvestmentManager/amount-exceeds-deposit-limits"
        );

        uint256 depositPrice = calculateDepositPrice(owner, liquidityPool);
        require(depositPrice != 0, "LiquidityPool/deposit-token-price-0");

        uint128 _trancheTokenAmount = _calculateTrancheTokenAmount(_currencyAmount, liquidityPool, depositPrice);
        _deposit(_trancheTokenAmount, _currencyAmount, liquidityPool, owner, receiver);
        trancheTokenAmount = uint256(_trancheTokenAmount);
    }

    /// @notice Processes owner's currency deposit / investment after the epoch has been executed on Centrifuge.
    ///         In case owner's invest order was fulfilled on Centrifuge during epoch execution MaxDeposit and MaxMint are increased
    ///         and trancheTokens can be transferred to owner's wallet on calling processDeposit or processMint.
    ///         Note: The currency amount required to fulfill the invest order is already locked in escrow upon calling requestDeposit.
    ///         Note: The tranche tokens are already minted on collectInvest and are deposited to the escrow account until the owner calls mint, or deposit.
    ///         Note: The tranche tokens are transferred to the receivers wallet.             
    /// @dev    currencyAmount return value is type of uint256 to be compliant with EIP4626 LiquidityPool interface
    /// @return currencyAmount the amount of liquidityPool assets invested and locked in escrow in order
    ///         for the amount of tranche tokens received after successful investment into the pool.
    function processMint(address liquidityPool, uint256 trancheTokenAmount, address receiver, address owner)
        public
        auth
        returns (uint256 currencyAmount)
    {
        uint128 _trancheTokenAmount = _toUint128(trancheTokenAmount);
        require(
            (_trancheTokenAmount <= orderbook[owner][liquidityPool].maxMint && _trancheTokenAmount != 0),
            "InvestmentManager/amount-exceeds-mint-limits"
        );

        uint256 depositPrice = calculateDepositPrice(owner, liquidityPool);
        require(depositPrice != 0, "LiquidityPool/deposit-token-price-0");

        uint128 _currencyAmount = _calculateCurrencyAmount(_trancheTokenAmount, liquidityPool, depositPrice);
        _deposit(_trancheTokenAmount, _currencyAmount, liquidityPool, owner, receiver);
        currencyAmount = uint256(_currencyAmount);
    }

    function _deposit(uint128 trancheTokenAmount, uint128 currencyAmount, address liquidityPool, address owner, address receiver)
        internal
    {
        LiquidityPoolLike lPool = LiquidityPoolLike(liquidityPool);

        // Decrease the deposit limits
        LPValues storage lpValues = orderbook[owner][liquidityPool];
        lpValues.maxDeposit = lpValues.maxDeposit < currencyAmount ? 0 : lpValues.maxDeposit - currencyAmount;
        lpValues.maxMint = lpValues.maxMint < trancheTokenAmount ? 0 : lpValues.maxMint - trancheTokenAmount;

        // Transfer the tranche tokens to the user
        require(
            lPool.transferFrom(address(escrow), receiver, trancheTokenAmount),
            "InvestmentManager/tranche-tokens-transfer-failed"
        );

        emit ProcessDeposit(liquidityPool, owner, currencyAmount, trancheTokenAmount);
    }

    /// @dev    Processes user's tranche Token redemption after the epoch has been executed on Centrifuge.
    ///         In case user's redemption order was fulfilled on Centrifuge during epoch execution MaxRedeem and MaxWithdraw
    ///         are increased and LiquidityPool currency can be transferred to user's wallet on calling processRedeem or processWithdraw.
    ///         Note: The trancheTokenAmount required to fulfill the redemption order was already locked in escrow
    ///         upon calling requestRedeem and burned upon collectRedeem.
    /// @notice currencyAmount return value is type of uint256 to be compliant with EIP4626 LiquidityPool interface
    /// @return currencyAmount the amount of liquidityPool assets received for the amount of redeemed/burned tranche tokens.
    function processRedeem(address liquidityPool, uint256 trancheTokenAmount, address receiver, address user)
        public
        auth
        returns (uint256 currencyAmount)
    {
        uint128 _trancheTokenAmount = _toUint128(trancheTokenAmount);
        require( _trancheTokenAmount <= orderbook[user][liquidityPool].maxRedeem && _trancheTokenAmount != 0, "InvestmentManager/amount-exceeds-redeem-limits"
        );

        uint256 redeemPrice = calculateRedeemPrice(user, liquidityPool);
        require(redeemPrice != 0, "LiquidityPool/redeem-token-price-0");

        uint128 _currencyAmount = _calculateCurrencyAmount(_trancheTokenAmount, liquidityPool, redeemPrice);
        _redeem(_trancheTokenAmount, _currencyAmount, liquidityPool, receiver, user);
        currencyAmount = uint256(_currencyAmount);
    }

    /// @dev    Processes user's tranche token redemption after the epoch has been executed on Centrifuge.
    ///         In case user's redemption order was fulfilled on Centrifuge during epoch execution MaxRedeem and MaxWithdraw
    ///         are increased and LiquidityPool currency can be transferred to user's wallet on calling processRedeem or processWithdraw.
    ///         Note: The trancheTokenAmount required to fulfill the redemption order was already locked in escrow upon calling requestRedeem and burned upon collectRedeem.
    /// @notice trancheTokenAmount return value is type of uint256 to be compliant with EIP4626 LiquidityPool interface
    /// @return trancheTokenAmount the amount of trancheTokens redeemed/burned required to receive the currencyAmount payout/withdrawal.
    function processWithdraw(address liquidityPool, uint256 currencyAmount, address receiver, address user)
        public
        auth
        returns (uint256 trancheTokenAmount)
    {
        uint128 _currencyAmount = _toUint128(currencyAmount);
        require(
            (_currencyAmount <= orderbook[user][liquidityPool].maxWithdraw && _currencyAmount != 0),
            "InvestmentManager/amount-exceeds-withdraw-limits"
        );

        uint256 redeemPrice = calculateRedeemPrice(user, liquidityPool);
        require(redeemPrice != 0, "LiquidityPool/redeem-token-price-0");

        uint128 _trancheTokenAmount = _calculateTrancheTokenAmount(_currencyAmount, liquidityPool, redeemPrice);
        _redeem(_trancheTokenAmount, _currencyAmount, liquidityPool, receiver, user);
        trancheTokenAmount = uint256(_trancheTokenAmount);
    }

    function _redeem(
        uint128 trancheTokenAmount,
        uint128 currencyAmount,
        address liquidityPool,
        address receiver,
        address user
    ) internal {
        LiquidityPoolLike lPool = LiquidityPoolLike(liquidityPool);

        // Decrease the redemption limits
        LPValues storage lpValues = orderbook[user][liquidityPool];
        lpValues.maxWithdraw = lpValues.maxWithdraw < currencyAmount ? 0 : lpValues.maxWithdraw - currencyAmount;
        lpValues.maxRedeem = lpValues.maxRedeem < trancheTokenAmount ? 0 : lpValues.maxRedeem - trancheTokenAmount;

        // Transfer the currency to the user
        userEscrow.transferOut(lPool.asset(), user, receiver, currencyAmount);

        emit ProcessRedeem(liquidityPool, user, currencyAmount, trancheTokenAmount);
    }

    // --- Helpers ---
    function calculateDepositPrice(address user, address liquidityPool) public view returns (uint256 depositPrice) {
        LPValues storage lpValues = orderbook[user][liquidityPool];
        if (lpValues.maxMint == 0) {
            return 0;
        }

        depositPrice = _calculatePrice(lpValues.maxDeposit, lpValues.maxMint, liquidityPool);
    }

    function calculateRedeemPrice(address user, address liquidityPool) public view returns (uint256 redeemPrice) {
        LPValues storage lpValues = orderbook[user][liquidityPool];
        if (lpValues.maxRedeem == 0) {
            return 0;
        }

        redeemPrice = _calculatePrice(lpValues.maxWithdraw, lpValues.maxRedeem, liquidityPool);
    }

    function _calculatePrice(uint128 currencyAmount, uint128 trancheTokenAmount, address liquidityPool)
        public
        view
        returns (uint256 depositPrice)
    {
        (uint8 currencyDecimals, uint8 trancheTokenDecimals) = _getPoolDecimals(liquidityPool);
        uint256 currencyAmountInPriceDecimals = _toPriceDecimals(currencyAmount, currencyDecimals);
        uint256 trancheTokenAmountInPriceDecimals = _toPriceDecimals(trancheTokenAmount, trancheTokenDecimals);

        depositPrice = currencyAmountInPriceDecimals.mulDiv(
            10 ** PRICE_DECIMALS, trancheTokenAmountInPriceDecimals, MathLib.Rounding.Down
        );
    }

    function _updateLiquidityPoolPrice(address liquidityPool, uint128 currencyPayout, uint128 trancheTokensPayout)
        internal
    {
        uint128 price = _toUint128(_calculatePrice(currencyPayout, trancheTokensPayout, liquidityPool));
        LiquidityPoolLike(liquidityPool).updatePrice(price);
    }

    function _calculateTrancheTokenAmount(uint128 currencyAmount, address liquidityPool, uint256 price)
        internal
        view
        returns (uint128 trancheTokenAmount)
    {
        (uint8 currencyDecimals, uint8 trancheTokenDecimals) = _getPoolDecimals(liquidityPool);

        uint256 currencyAmountInPriceDecimals = _toPriceDecimals(currencyAmount, currencyDecimals).mulDiv(
            10 ** PRICE_DECIMALS, price, MathLib.Rounding.Down
        );

        trancheTokenAmount = _fromPriceDecimals(currencyAmountInPriceDecimals, trancheTokenDecimals);
    }

    function _calculateCurrencyAmount(uint128 trancheTokenAmount, address liquidityPool, uint256 price)
        internal
        view
        returns (uint128 currencyAmount)
    {
        (uint8 currencyDecimals, uint8 trancheTokenDecimals) = _getPoolDecimals(liquidityPool);

        uint256 currencyAmountInPriceDecimals = _toPriceDecimals(trancheTokenAmount, trancheTokenDecimals).mulDiv(
            price, 10 ** PRICE_DECIMALS, MathLib.Rounding.Down
        );

        currencyAmount = _fromPriceDecimals(currencyAmountInPriceDecimals, currencyDecimals);
    }

    /// @dev    Safe type conversion from uint256 to uint128. Revert if value is too big to be stored with uint128. Avoid data loss.
    /// @return value - safely converted without data loss
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
}
