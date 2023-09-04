// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import {Auth} from "./util/Auth.sol";
import {Math} from "./util/Math.sol";

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

interface LiquidityPoolLike {
    function rely(address) external;
    // restricted token functions
    function hasMember(address) external returns (bool);
    function file(bytes32 what, address data) external;
    // erc20 functions
    function mint(address, uint256) external;
    function burn(address, uint256) external;
    function balanceOf(address) external returns (uint256);
    function transferFrom(address, address, uint256) external returns (bool);
    function decimals() external view returns (uint8);
    // 4626 functions
    function asset() external view returns (address);
    // centrifuge chain info functions
    function poolId() external returns (uint64);
    function trancheId() external returns (bytes16);
}

interface PoolManagerLike {
    function currencyIdToAddress(uint128 currencyId) external view returns (address);
    function currencyAddressToId(address addr) external view returns (uint128);
    function getTrancheToken(uint64 poolId, bytes16 trancheId) external view returns (address);
    function getLiquidityPool(uint64 poolId, bytes16 trancheId, address currency) external view returns (address);
    function isAllowedAsPoolCurrency(uint64 poolId, address currencyAddress) external view returns (bool);
}

interface ERC20Like {
    function approve(address token, address spender, uint256 value) external;
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function balanceOf(address) external returns (uint256);
    function decimals() external view returns (uint8);
}

interface EscrowLike {
    function approve(address token, address spender, uint256 value) external;
}

interface UserEscrowLike {
    function transferIn(address token, address source, address destination, uint256 amount) external;
    function transferOut(address token, address destination, uint256 amount) external;
}

/// @dev liquidity pool orders and deposit/redemption limits per user
struct LPValues {
    uint128 maxDeposit; // denominated in assets
    uint128 maxMint; // denominated in tranche tokens
    uint128 maxWithdraw; // denominated in assets
    uint128 maxRedeem; // denominated in tranche tokens
}

contract InvestmentManager is Auth {
    using Math for uint128;

    uint8 public constant PRICE_DECIMALS = 18; // Prices are fixed-point integers with 18 decimals

    EscrowLike public immutable escrow;
    UserEscrowLike public immutable userEscrow;

    GatewayLike public gateway;
    PoolManagerLike public poolManager;

    mapping(address => mapping(address => LPValues)) public orderbook; // Liquidity pool orders & limits per user

    // --- Events ---
    event File(bytes32 indexed what, address data);
    event DepositProcessed(address indexed liquidityPool, address indexed user, uint128 indexed currencyAmount);
    event RedemptionProcessed(address indexed liquidityPool, address indexed user, uint128 indexed trancheTokenAmount);

    constructor(address escrow_, address userEscrow_) {
        escrow = EscrowLike(escrow_);
        userEscrow = UserEscrowLike(userEscrow_);

        wards[msg.sender] = 1;
        emit Rely(msg.sender);
    }

    /// @dev gateway must be message.sender. permissions check for incoming message handling.
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
    /// @dev request tranche token redemption. Liquidity pools have to request investments from the centrifuge chain before actual tranche token payouts can be done.
    /// The deposit requests are added to the order book on centrifuge chain. Once the next epoch is executed on centrifuge chain, liquidity pools can proceed with tranche token payouts in case their orders got fullfilled.
    /// @notice The user currency amount equired to fullfill the deposit request have to be locked, even though the tranche token payout can only happen after epoch execution.
    /// This function automatically closed all the outstading redemption orders for the user.
    function requestDeposit(uint256 currencyAmount, address user) public auth {
        address liquidityPool = msg.sender;
        LiquidityPoolLike lPool = LiquidityPoolLike(liquidityPool);
        address currency = lPool.asset();
        uint128 _currencyAmount = _toUint128(currencyAmount);

        // check if liquidity pool currency is supported by the centrifuge pool
        require(
            poolManager.isAllowedAsPoolCurrency(lPool.poolId(), currency), "InvestmentManager/currency-not-supported"
        );
        // check if user is allowed to hold the restriced liquidity pool tokens
        require(
            _isAllowedToInvest(lPool.poolId(), lPool.trancheId(), currency, user),
            "InvestmentManager/tranche-tokens-not-supported"
        );

        if (_currencyAmount == 0) {
            // case: outstanding redemption orders only needed to be cancelled
            gateway.cancelInvestOrder(
                lPool.poolId(), lPool.trancheId(), user, poolManager.currencyAddressToId(lPool.asset())
            );
            return;
        }

        // transfer the differene between required and locked currency from user to escrwo
        require(
            ERC20Like(currency).transferFrom(user, address(escrow), _currencyAmount),
            "InvestmentManager/currency-transfer-failed"
        );

        gateway.increaseInvestOrder(
            lPool.poolId(), lPool.trancheId(), user, poolManager.currencyAddressToId(lPool.asset()), _currencyAmount
        );
    }

    /// @dev request tranche token redemption. Liquidity pools have to request redemptions from the centrifuge chain before actual currency payouts can be done.
    /// The redemption requests are added to the order book on centrifuge chain. Once the next epoch is executed on centrifuge chain, liquidity pools can proceed with currency payouts in case their orders got fullfilled.
    /// @notice The user tranche tokens required to fullfill the redemption request have to be locked, even though the currency payout can only happen after epoch execution.
    /// This function automatically closed all the outstading investment orders for the user.
    function requestRedeem(uint256 trancheTokenAmount, address user) public auth {
        address liquidityPool = msg.sender;
        LiquidityPoolLike lPool = LiquidityPoolLike(liquidityPool);
        uint128 _trancheTokenAmount = _toUint128(trancheTokenAmount);

        // check if liquidity pool currency is supported by the centrifuge pool
        require(
            poolManager.isAllowedAsPoolCurrency(lPool.poolId(), lPool.asset()),
            "InvestmentManager/currency-not-supported"
        );
        // check if user is allowed to hold the restriced liquidity pool tokens
        require(
            _isAllowedToInvest(lPool.poolId(), lPool.trancheId(), lPool.asset(), user),
            "InvestmentManager/tranche-tokens-not-supported"
        );

        if (_trancheTokenAmount == 0) {
            // case: outstanding redeem orders will be cancelled
            gateway.cancelRedeemOrder(
                lPool.poolId(), lPool.trancheId(), user, poolManager.currencyAddressToId(lPool.asset())
            );
            return;
        }

        // transfer the differene between required and locked tranche tokens from user to escrow
        require(
            lPool.transferFrom(user, address(escrow), _trancheTokenAmount),
            "InvestmentManager/tranche-token-transfer-failed"
        );

        gateway.increaseRedeemOrder(
            lPool.poolId(), lPool.trancheId(), user, poolManager.currencyAddressToId(lPool.asset()), _trancheTokenAmount
        );
    }

    function decreaseDepositRequest(uint256 currencyAmount, address user) public auth {
        LiquidityPoolLike liquidityPool = LiquidityPoolLike(msg.sender);
        require(liquidityPool.hasMember(user), "InvestmentManager/not-a-member");
        gateway.decreaseInvestOrder(
            liquidityPool.poolId(),
            liquidityPool.trancheId(),
            user,
            poolManager.currencyAddressToId(liquidityPool.asset()),
            _toUint128(currencyAmount)
        );
    }

    function decreaseRedeemRequest(uint256 trancheTokenAmount, address user) public auth {
        LiquidityPoolLike liquidityPool = LiquidityPoolLike(msg.sender);
        require(liquidityPool.hasMember(user), "InvestmentManager/not-a-member");
        gateway.decreaseRedeemOrder(
            liquidityPool.poolId(),
            liquidityPool.trancheId(),
            user,
            poolManager.currencyAddressToId(liquidityPool.asset()),
            _toUint128(trancheTokenAmount)
        );
    }

    function collectDeposit(address user) public auth {
        LiquidityPoolLike liquidityPool = LiquidityPoolLike(msg.sender);
        require(liquidityPool.hasMember(user), "InvestmentManager/not-a-member");
        gateway.collectInvest(
            liquidityPool.poolId(),
            liquidityPool.trancheId(),
            user,
            poolManager.currencyAddressToId(liquidityPool.asset())
        );
    }

    function collectRedeem(address user) public auth {
        LiquidityPoolLike liquidityPool = LiquidityPoolLike(msg.sender);
        require(liquidityPool.hasMember(user), "InvestmentManager/not-a-member");
        gateway.collectRedeem(
            liquidityPool.poolId(),
            liquidityPool.trancheId(),
            user,
            poolManager.currencyAddressToId(liquidityPool.asset())
        );
    }

    // --- Incoming message handling ---
    function handleExecutedCollectInvest(
        uint64 poolId,
        bytes16 trancheId,
        address recipient,
        uint128 currency,
        uint128 currencyInvested,
        uint128 tokensPayout
    ) public onlyGateway {
        require(currencyInvested != 0, "InvestmentManager/zero-invest");
        address _currency = poolManager.currencyIdToAddress(currency);
        address liquidityPool = poolManager.getLiquidityPool(poolId, trancheId, _currency);
        require(liquidityPool != address(0), "InvestmentManager/tranche-does-not-exist");

        LPValues storage lpValues = orderbook[recipient][liquidityPool];
        lpValues.maxDeposit = lpValues.maxDeposit + currencyInvested;
        lpValues.maxMint = lpValues.maxMint + tokensPayout;

        LiquidityPoolLike(liquidityPool).mint(address(escrow), tokensPayout); // mint to escrow. Recepeint can claim by calling withdraw / redeem
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

        require(
            ERC20Like(_currency).transferFrom(address(escrow), user, currencyPayout),
            "InvestmentManager/currency-transfer-failed"
        );
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

        require(LiquidityPoolLike(liquidityPool).hasMember(user), "InvestmentManager/not-a-member");

        require(
            LiquidityPoolLike(liquidityPool).transferFrom(address(escrow), user, trancheTokenPayout),
            "InvestmentManager/trancheTokens-transfer-failed"
        );
    }

    // --- View functions ---
    /// @return currencyAmount is type of uin256 to support the EIP4626 Liquidity Pool interface
    function maxDeposit(address user, address liquidityPool) public view returns (uint256 currencyAmount) {
        currencyAmount = uint256(orderbook[user][liquidityPool].maxDeposit);
    }

    /// @return trancheTokenAmount type of uin256 to support the EIP4626 Liquidity Pool interface
    function maxMint(address user, address liquidityPool) public view returns (uint256 trancheTokenAmount) {
        trancheTokenAmount = uint256(orderbook[user][liquidityPool].maxMint);
    }

    /// @return currencyAmount type of uin256 to support the EIP4626 Liquidity Pool interface
    function maxWithdraw(address user, address liquidityPool) public view returns (uint256 currencyAmount) {
        currencyAmount = uint256(orderbook[user][liquidityPool].maxWithdraw);
    }

    /// @return trancheTokenAmount type of uin256 to support the EIP4626 Liquidity Pool interface
    function maxRedeem(address user, address liquidityPool) public view returns (uint256 trancheTokenAmount) {
        trancheTokenAmount = uint256(orderbook[user][liquidityPool].maxRedeem);
    }

    /// @return trancheTokenAmount is type of uin256 to support the EIP4626 Liquidity Pool interface
    function previewDeposit(address user, address liquidityPool, uint256 currencyAmount)
        public
        view
        returns (uint256 trancheTokenAmount)
    {
        uint128 depositPrice = calculateDepositPrice(user, liquidityPool);
        if (depositPrice == 0) return 0;

        trancheTokenAmount =
            uint256(_calculateTrancheTokenAmount(_toUint128(currencyAmount), liquidityPool, depositPrice));
    }

    /// @return currencyAmount is type of uin256 to support the EIP4626 Liquidity Pool interface
    function previewMint(address user, address liquidityPool, uint256 trancheTokenAmount)
        public
        view
        returns (uint256 currencyAmount)
    {
        uint128 depositPrice = calculateDepositPrice(user, liquidityPool);
        if (depositPrice == 0) return 0;

        currencyAmount = uint256(_calculateCurrencyAmount(_toUint128(trancheTokenAmount), liquidityPool, depositPrice));
    }

    /// @return trancheTokenAmount is type of uin256 to support the EIP4626 Liquidity Pool interface
    function previewRedeem(address user, address liquidityPool, uint256 currencyAmount)
        public
        view
        returns (uint256 trancheTokenAmount)
    {
        uint128 redeemPrice = calculateRedeemPrice(user, liquidityPool);
        if (redeemPrice == 0) return 0;

        trancheTokenAmount =
            uint256(_calculateTrancheTokenAmount(_toUint128(currencyAmount), liquidityPool, redeemPrice));
    }

    /// @return currencyAmount is type of uin256 to support the EIP4626 Liquidity Pool interface
    function previewWithdraw(address user, address liquidityPool, uint256 trancheTokenAmount)
        public
        view
        returns (uint256 currencyAmount)
    {
        uint128 redeemPrice = calculateRedeemPrice(user, liquidityPool);
        if (redeemPrice == 0) return 0;

        currencyAmount = uint256(_calculateCurrencyAmount(_toUint128(trancheTokenAmount), liquidityPool, redeemPrice));
    }

    // --- Liquidity Pool processing functions ---
    /// @dev processes user's currency deposit / investment after the epoch has been executed on Centrifuge chain.
    /// In case user's invest order was fullfilled on Centrifuge chain during epoch execution MaxDeposit and MaxMint are increased and trancheTokens can be transferred to user's wallet on calling processDeposit.
    /// Note: The currency required to fullfill the invest order is already locked in escrow upon calling requestDeposit.
    /// @notice trancheTokenAmount return value is type of uint256 to be compliant with EIP4626 LiquidityPool interface
    /// @return trancheTokenAmount the amount of trancheTokens transferred to the user's wallet after successful depoit
    function processDeposit(address user, uint256 currencyAmount) public auth returns (uint256 trancheTokenAmount) {
        address liquidityPool = msg.sender;
        uint128 _currencyAmount = _toUint128(currencyAmount);
        require(
            (_currencyAmount <= orderbook[user][liquidityPool].maxDeposit && _currencyAmount != 0),
            "InvestmentManager/amount-exceeds-deposit-limits"
        );

        uint128 depositPrice = calculateDepositPrice(user, liquidityPool);
        require(depositPrice != 0, "LiquidityPool/deposit-token-price-0");

        uint128 _trancheTokenAmount = _calculateTrancheTokenAmount(_currencyAmount, liquidityPool, depositPrice);
        _deposit(_trancheTokenAmount, _currencyAmount, liquidityPool, user);
        trancheTokenAmount = uint256(_trancheTokenAmount);
    }

    /// @dev processes user's currency deposit / investment after the epoch has been executed on Centrifuge chain.
    /// In case user's invest order was fullfilled on Centrifuge chain during epoch execution MaxDeposit and MaxMint are increased and trancheTokens can be transferred to user's wallet on calling processDeposit or processMint.
    /// Note: The currency amount required to fullfill the invest order is already locked in escrow upon calling requestDeposit.
    /// Note: The tranche tokens are already minted on collectInvest and are deposited to the escrow account until the users calls mint, or deposit.
    /// @notice currencyAmount return value is type of uint256 to be compliant with EIP4626 LiquidityPool interface
    /// @return currencyAmount the amount of liquidityPool assets invested and locked in escrow in order for the amount of tranche received after successful investment into the pool.
    function processMint(address user, uint256 trancheTokenAmount) public auth returns (uint256 currencyAmount) {
        address liquidityPool = msg.sender;
        uint128 _trancheTokenAmount = _toUint128(trancheTokenAmount);
        require(
            (_trancheTokenAmount <= orderbook[user][liquidityPool].maxMint && _trancheTokenAmount != 0),
            "InvestmentManager/amount-exceeds-mint-limits"
        );

        uint128 depositPrice = calculateDepositPrice(user, liquidityPool);
        require(depositPrice != 0, "LiquidityPool/deposit-token-price-0");

        uint128 _currencyAmount = _calculateCurrencyAmount(_trancheTokenAmount, liquidityPool, depositPrice);
        _deposit(_trancheTokenAmount, _currencyAmount, liquidityPool, user);
        currencyAmount = uint256(_currencyAmount);
    }

    function _deposit(uint128 trancheTokenAmount, uint128 currencyAmount, address liquidityPool, address user)
        internal
    {
        LiquidityPoolLike lPool = LiquidityPoolLike(liquidityPool);

        _decreaseDepositLimits(user, liquidityPool, currencyAmount, trancheTokenAmount); // decrease the possible deposit limits
        require(lPool.hasMember(user), "InvestmentManager/trancheTokens-not-a-member");
        require(
            lPool.transferFrom(address(escrow), user, trancheTokenAmount),
            "InvestmentManager/trancheTokens-transfer-failed"
        );

        emit DepositProcessed(liquidityPool, user, currencyAmount);
    }

    /// @dev processes user's trancheToken redemption after the epoch has been executed on Centrifuge chain.
    /// In case user's redempion order was fullfilled on Centrifuge chain during epoch execution MaxRedeem and MaxWithdraw are increased and LiquidityPool currency can be transferred to user's wallet on calling processRedeem or processWithdraw.
    /// Note: The trancheToken amount required to fullfill the redemption order was already locked in escrow upon calling requestRedeem and burned upon collectRedeem.
    /// @notice currencyAmount return value is type of uint256 to be compliant with EIP4626 LiquidityPool interface
    /// @return currencyAmount the amount of liquidityPool assets received for the amount of redeemed/burned trancheTokens.
    function processRedeem(uint256 trancheTokenAmount, address receiver, address user)
        public
        auth
        returns (uint256 currencyAmount)
    {
        address liquidityPool = msg.sender;
        uint128 _trancheTokenAmount = _toUint128(trancheTokenAmount);
        require(
            (_trancheTokenAmount <= orderbook[user][liquidityPool].maxRedeem && _trancheTokenAmount != 0),
            "InvestmentManager/amount-exceeds-redeem-limits"
        );

        uint128 redeemPrice = calculateRedeemPrice(user, liquidityPool);
        require(redeemPrice != 0, "LiquidityPool/redeem-token-price-0");

        uint128 _currencyAmount = _calculateCurrencyAmount(_trancheTokenAmount, liquidityPool, redeemPrice);
        _redeem(_trancheTokenAmount, _currencyAmount, liquidityPool, receiver, user);
        currencyAmount = uint256(_currencyAmount);
    }

    /// @dev processes user's trancheToken redemption after the epoch has been executed on Centrifuge chain.
    /// In case user's redempion order was fullfilled on Centrifuge chain during epoch execution MaxRedeem and MaxWithdraw are increased and LiquidityPool currency can be transferred to user's wallet on calling processRedeem or processWithdraw.
    /// Note: The trancheToken amount required to fullfill the redemption order was already locked in escrow upon calling requestRedeem and burned upon collectRedeem.
    /// @notice trancheTokenAmount return value is type of uint256 to be compliant with EIP4626 LiquidityPool interface
    /// @return trancheTokenAmount the amount of trancheTokens redeemed/burned required to receive the currencyAmount payout/withdrawel.
    function processWithdraw(uint256 currencyAmount, address receiver, address user)
        public
        auth
        returns (uint256 trancheTokenAmount)
    {
        address liquidityPool = msg.sender;
        uint128 _currencyAmount = _toUint128(currencyAmount);
        require(
            (_currencyAmount <= orderbook[user][liquidityPool].maxWithdraw && _currencyAmount != 0),
            "InvestmentManager/amount-exceeds-withdraw-limits"
        );

        uint128 redeemPrice = calculateRedeemPrice(user, liquidityPool);
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

        _decreaseRedemptionLimits(user, liquidityPool, currencyAmount, trancheTokenAmount); // decrease the possible deposit limits
        userEscrow.transferOut(lPool.asset(), receiver, currencyAmount);

        emit RedemptionProcessed(liquidityPool, user, trancheTokenAmount);
    }

    // --- Helpers ---
    function calculateDepositPrice(address user, address liquidityPool) public view returns (uint128 depositPrice) {
        LPValues storage lpValues = orderbook[user][liquidityPool];
        if (lpValues.maxMint == 0) {
            return 0;
        }

        (uint8 poolDecimals, uint8 currencyDecimals, uint8 trancheTokenDecimals) = _getPoolDecimals(liquidityPool);
        uint128 maxDepositInPoolDecimals = _toPoolDecimals(lpValues.maxDeposit, currencyDecimals, liquidityPool);
        uint128 maxMintInPoolDecimals = _toPoolDecimals(lpValues.maxMint, trancheTokenDecimals, liquidityPool);

        depositPrice =
            _toUint128(maxDepositInPoolDecimals.mulDiv(10 ** poolDecimals, maxMintInPoolDecimals, Math.Rounding.Down));
    }

    function calculateRedeemPrice(address user, address liquidityPool) public view returns (uint128 redeemPrice) {
        LPValues storage lpValues = orderbook[user][liquidityPool];
        if (lpValues.maxRedeem == 0) {
            return 0;
        }

        (uint8 poolDecimals, uint8 currencyDecimals, uint8 trancheTokenDecimals) = _getPoolDecimals(liquidityPool);
        uint128 maxWithdrawInPoolDecimals = _toPoolDecimals(lpValues.maxWithdraw, currencyDecimals, liquidityPool);
        uint128 maxRedeemInPoolDecimals = _toPoolDecimals(lpValues.maxRedeem, trancheTokenDecimals, liquidityPool);

        redeemPrice = _toUint128(
            maxWithdrawInPoolDecimals.mulDiv(10 ** poolDecimals, maxRedeemInPoolDecimals, Math.Rounding.Down)
        );
    }

    function _calculateTrancheTokenAmount(uint128 currencyAmount, address liquidityPool, uint128 price)
        internal
        view
        returns (uint128 trancheTokenAmount)
    {
        (uint8 poolDecimals, uint8 currencyDecimals, uint8 trancheTokenDecimals) = _getPoolDecimals(liquidityPool);

        uint128 currencyAmountInPoolDecimals = _toUint128(
            _toPoolDecimals(currencyAmount, currencyDecimals, liquidityPool).mulDiv(
                10 ** poolDecimals, price, Math.Rounding.Down
            )
        );

        trancheTokenAmount = _fromPoolDecimals(currencyAmountInPoolDecimals, trancheTokenDecimals, liquidityPool);
    }

    function _calculateCurrencyAmount(uint128 trancheTokenAmount, address liquidityPool, uint128 price)
        internal
        view
        returns (uint128 currencyAmount)
    {
        (uint8 poolDecimals, uint8 currencyDecimals, uint8 trancheTokenDecimals) = _getPoolDecimals(liquidityPool);

        uint128 currencyAmountInPoolDecimals = _toUint128(
            _toPoolDecimals(trancheTokenAmount, trancheTokenDecimals, liquidityPool).mulDiv(
                price, 10 ** poolDecimals, Math.Rounding.Down
            )
        );

        currencyAmount = _fromPoolDecimals(currencyAmountInPoolDecimals, currencyDecimals, liquidityPool);
    }

    function _decreaseDepositLimits(address user, address liquidityPool, uint128 _currency, uint128 trancheTokens)
        internal
    {
        LPValues storage lpValues = orderbook[user][liquidityPool];
        if (lpValues.maxDeposit < _currency) {
            lpValues.maxDeposit = 0;
        } else {
            lpValues.maxDeposit = lpValues.maxDeposit - _currency;
        }
        if (lpValues.maxMint < trancheTokens) {
            lpValues.maxMint = 0;
        } else {
            lpValues.maxMint = lpValues.maxMint - trancheTokens;
        }
    }

    function _decreaseRedemptionLimits(address user, address liquidityPool, uint128 _currency, uint128 trancheTokens)
        internal
    {
        LPValues storage lpValues = orderbook[user][liquidityPool];
        if (lpValues.maxWithdraw < _currency) {
            lpValues.maxWithdraw = 0;
        } else {
            lpValues.maxWithdraw = lpValues.maxWithdraw - _currency;
        }
        if (lpValues.maxRedeem < trancheTokens) {
            lpValues.maxRedeem = 0;
        } else {
            lpValues.maxRedeem = lpValues.maxRedeem - trancheTokens;
        }
    }

    function _isAllowedToInvest(uint64 poolId, bytes16 trancheId, address currency, address user)
        internal
        returns (bool)
    {
        address liquidityPool = poolManager.getLiquidityPool(poolId, trancheId, currency);
        require(liquidityPool != address(0), "InvestmentManager/unknown-liquidity-pool");
        require(LiquidityPoolLike(liquidityPool).hasMember(user), "InvestmentManager/not-a-member");
        return true;
    }

    /// @dev safe type conversion from uint256 to uint128. Revert if value is too big to be stored with uint128. Avoid data loss.
    /// @return value - safely converted without data loss
    function _toUint128(uint256 _value) internal pure returns (uint128 value) {
        if (_value > type(uint128).max) {
            revert();
        } else {
            value = uint128(_value);
        }
    }

    /// @dev convert decimals of the value into the pool decimals
    function _toPoolDecimals(uint128 _value, uint8 decimals, address liquidityPool)
        internal
        view
        returns (uint128 value)
    {
        (uint8 maxDecimals,,) = _getPoolDecimals(liquidityPool);
        if (maxDecimals == decimals) return _value;
        return _toUint128(_value * 10 ** (maxDecimals - decimals));
    }

    /// @dev convert decimals of the value from the pool decimals back to the intended decimals
    function _fromPoolDecimals(uint128 _value, uint8 decimals, address liquidityPool)
        internal
        view
        returns (uint128 value)
    {
        (uint8 maxDecimals,,) = _getPoolDecimals(liquidityPool);
        if (maxDecimals == decimals) return _value;
        return _toUint128(_value / 10 ** (maxDecimals - decimals));
    }

    /// @dev pool decimals are the max of the currency decimals and the tranche token decimals
    function _getPoolDecimals(address liquidityPool)
        internal
        view
        returns (uint8 poolDecimals, uint8 currencyDecimals, uint8 trancheTokenDecimals)
    {
        currencyDecimals = ERC20Like(LiquidityPoolLike(liquidityPool).asset()).decimals();
        trancheTokenDecimals = LiquidityPoolLike(liquidityPool).decimals();
        poolDecimals = uint8(Math.max(currencyDecimals, trancheTokenDecimals));
    }
}
