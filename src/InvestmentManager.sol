// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.18;
pragma abicoder v2;

import {TrancheTokenFactoryLike, LiquidityPoolFactoryLike} from "./util/Factory.sol";
import {MemberlistLike} from "./token/Memberlist.sol";
import "./util/Auth.sol";
import "./util/Math.sol";

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

interface TokenManagerLike {
    function currencyIdToAddress(uint128 currencyId) external view returns (address);
    function currencyAddressToId(address addr) external view returns (uint128);
}

interface ERC20Like {
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function balanceOf(address) external returns (uint256);
    function decimals() external view returns (uint8);
}

interface ERC2771Like {
    function addLiquidityPool(address forwarder) external;
}

interface EscrowLike {
    function approve(address token, address spender, uint256 value) external;
}

interface AuthLike {
    function rely(address usr) external;
}

/// @dev Centrifuge pools
struct Pool {
    uint64 poolId;
    uint256 createdAt;
    bool isActive;
    mapping(bytes16 => Tranche) tranches;
    mapping(address => bool) allowedCurrencies;
}

/// @dev Each Centrifuge pool is associated to 1 or more tranches
struct Tranche {
    address token;
    uint64 poolId;
    bytes16 trancheId;
    // important: the decimals of the leading pool currency. Liquidity Pool shares have to be denomatimated with the same precision.
    uint8 decimals;
    uint256 createdAt;
    string tokenName;
    string tokenSymbol;
    uint128 latestPrice;
    /// @dev Each tranche can have multiple liquidity pools deployed,
    /// each linked to a unique investment currency (asset)
    mapping(address => address) liquidityPools; // currency -> liquidity pool address
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

    mapping(uint64 => Pool) public pools; // Mapping of all deployed Centrifuge pools
    mapping(address => mapping(address => LPValues)) public orderbook; // Liquidity pool orders & limits per user

    GatewayLike public gateway;
    TokenManagerLike public tokenManager;
    EscrowLike public immutable escrow;

    LiquidityPoolFactoryLike public immutable liquidityPoolFactory;
    TrancheTokenFactoryLike public immutable trancheTokenFactory;

    // --- Events ---
    event File(bytes32 indexed what, address data);
    event PoolAdded(uint64 indexed poolId);
    event PoolCurrencyAllowed(uint128 indexed currency, uint64 indexed poolId);
    event TrancheAdded(uint64 indexed poolId, bytes16 indexed trancheId);
    event TrancheDeployed(uint64 indexed poolId, bytes16 indexed trancheId, address indexed token);
    event DepositProcessed(address indexed liquidityPool, address indexed user, uint128 indexed currencyAmount);
    event RedemptionProcessed(address indexed liquidityPool, address indexed user, uint128 indexed trancheTokenAmount);
    event LiquidityPoolDeployed(uint64 indexed poolId, bytes16 indexed trancheId, address indexed liquidityPoool);
    event TrancheTokenDeployed(uint64 indexed poolId, bytes16 indexed trancheId);

    constructor(address escrow_, address liquidityPoolFactory_, address trancheTokenFactory_) {
        escrow = EscrowLike(escrow_);
        liquidityPoolFactory = LiquidityPoolFactoryLike(liquidityPoolFactory_);
        trancheTokenFactory = TrancheTokenFactoryLike(trancheTokenFactory_);

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
        else if (what == "tokenManager") tokenManager = TokenManagerLike(data);
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
        LPValues storage lpValues = orderbook[user][liquidityPool];
        LiquidityPoolLike lPool = LiquidityPoolLike(liquidityPool);
        address currency = lPool.asset();
        uint128 _currencyAmount = _toUint128(currencyAmount);

        // check if liquidity pool currency is supported by the centrifuge pool
        require(_poolCurrencyCheck(lPool.poolId(), currency), "InvestmentManager/currency-not-supported");
        // check if user is allowed to hold the restriced liquidity pool tokens
        require(
            _liquidityPoolTokensCheck(lPool.poolId(), lPool.trancheId(), currency, user),
            "InvestmentManager/tranche-tokens-not-supported"
        );

        if (_currencyAmount == 0) {
            // case: outstanding redemption orders only needed to be cancelled
            gateway.cancelInvestOrder(
                lPool.poolId(), lPool.trancheId(), user, tokenManager.currencyAddressToId(lPool.asset())
            );
            return;
        }
        if (lpValues.maxWithdraw >= _currencyAmount) {
            // case: user has some claimable funds in escrow -> funds > depositRequest _currencyAmount
            uint128 redeemPrice = calculateRedeemPrice(user, liquidityPool);
            uint128 trancheTokenAmount = _calculateTrancheTokenAmount(_currencyAmount, liquidityPool, redeemPrice);
            _decreaseRedemptionLimits(user, liquidityPool, _currencyAmount, trancheTokenAmount);
        } else {
            uint128 transferAmount = _currencyAmount - lpValues.maxWithdraw;
            lpValues.maxWithdraw = 0;
            lpValues.maxRedeem = 0;

            // transfer the differene between required and locked currency from user to escrow
            require(ERC20Like(currency).balanceOf(user) >= transferAmount, "InvestmentManager/insufficient-balance");
            require(
                ERC20Like(currency).transferFrom(user, address(escrow), transferAmount),
                "InvestmentManager/currency-transfer-failed"
            );
        }
        gateway.increaseInvestOrder(
            lPool.poolId(), lPool.trancheId(), user, tokenManager.currencyAddressToId(lPool.asset()), _currencyAmount
        );
    }

    /// @dev request tranche token redemption. Liquidity pools have to request redemptions from the centrifuge chain before actual currency payouts can be done.
    /// The redemption requests are added to the order book on centrifuge chain. Once the next epoch is executed on centrifuge chain, liquidity pools can proceed with currency payouts in case their orders got fullfilled.
    /// @notice The user tranche tokens required to fullfill the redemption request have to be locked, even though the currency payout can only happen after epoch execution.
    /// This function automatically closed all the outstading investment orders for the user.
    function requestRedeem(uint256 trancheTokenAmount, address user) public auth {
        address liquidityPool = msg.sender;
        LPValues storage lpValues = orderbook[user][liquidityPool];
        LiquidityPoolLike lPool = LiquidityPoolLike(liquidityPool);
        uint128 _trancheTokenAmount = _toUint128(trancheTokenAmount);

        // check if liquidity pool currency is supported by the centrifuge pool
        require(_poolCurrencyCheck(lPool.poolId(), lPool.asset()), "InvestmentManager/currency-not-supported");
        // check if user is allowed to hold the restriced liquidity pool tokens
        require(
            _liquidityPoolTokensCheck(lPool.poolId(), lPool.trancheId(), lPool.asset(), user),
            "InvestmentManager/tranche-tokens-not-supported"
        );

        if (_trancheTokenAmount == 0) {
            // case: outstanding redeem orders will be cancelled
            gateway.cancelRedeemOrder(
                lPool.poolId(), lPool.trancheId(), user, tokenManager.currencyAddressToId(lPool.asset())
            );
            return;
        }

        if (lpValues.maxMint >= _trancheTokenAmount) {
            // case: user has unclaimed trancheTokens in escrow -> more than redemption request
            uint128 depositPrice = calculateDepositPrice(user, liquidityPool);
            uint128 currencyAmount = _calculateCurrencyAmount(_trancheTokenAmount, liquidityPool, depositPrice);
            _decreaseDepositLimits(user, liquidityPool, currencyAmount, _trancheTokenAmount);
        } else {
            uint256 transferAmount = _trancheTokenAmount - lpValues.maxMint;
            lpValues.maxDeposit = 0;
            lpValues.maxMint = 0;
            // transfer the differene between required and locked tranche tokens from user to escrow
            require(lPool.balanceOf(user) >= transferAmount, "InvestmentManager/insufficient-tranche-token-balance");
            require(
                lPool.transferFrom(user, address(escrow), transferAmount),
                "InvestmentManager/tranche-token-transfer-failed"
            );
        }
        gateway.increaseRedeemOrder(
            lPool.poolId(),
            lPool.trancheId(),
            user,
            tokenManager.currencyAddressToId(lPool.asset()),
            _trancheTokenAmount
        );
    }

    function collectInvest(uint64 poolId, bytes16 trancheId, address user, address currency) public auth {
        LiquidityPoolLike lPool = LiquidityPoolLike(msg.sender);
        require(lPool.hasMember(user), "InvestmentManager/not-a-member");
        require(_poolCurrencyCheck(poolId, currency), "InvestmentManager/currency-not-supported");
        gateway.collectInvest(poolId, trancheId, user, tokenManager.currencyAddressToId(currency));
    }

    function collectRedeem(uint64 poolId, bytes16 trancheId, address user, address currency) public auth {
        LiquidityPoolLike lPool = LiquidityPoolLike(msg.sender);
        require(lPool.hasMember(user), "InvestmentManager/not-a-member");
        require(_poolCurrencyCheck(poolId, currency), "InvestmentManager/currency-not-supported");
        gateway.collectRedeem(poolId, trancheId, user, tokenManager.currencyAddressToId(currency));
    }

    // --- Incoming message handling ---
    /// @dev new pool details from an existing centrifuge chain pool are added.
    /// @notice the function can only be executed by the gateway contract.
    function addPool(uint64 poolId) public onlyGateway {
        Pool storage pool = pools[poolId];
        require(pool.createdAt == 0, "InvestmentManager/pool-already-added");
        pool.poolId = poolId;
        pool.createdAt = block.timestamp;
        pool.isActive = true;
        emit PoolAdded(poolId);
    }

    /// @dev centrifuge pools can support multiple currencies for investing. this function adds a new supported currency to the pool details.
    /// Adding new currencies allow the creation of new liquidity pools for the underlying centrifuge chain pool.
    /// @notice the function can only be executed by the gateway contract.
    function allowPoolCurrency(uint64 poolId, uint128 currency) public onlyGateway {
        Pool storage pool = pools[poolId];
        require(pool.createdAt > 0, "InvestmentManager/invalid-pool");

        address currencyAddress = tokenManager.currencyIdToAddress(currency);
        require(currencyAddress != address(0), "InvestmentManager/unknown-currency");

        pools[poolId].allowedCurrencies[currencyAddress] = true;
        emit PoolCurrencyAllowed(currency, poolId);
    }

    /// @dev new tranche details from an existng centrifuge chain pool are added.
    /// @notice the function can only be executed by the gateway contract.
    function addTranche(
        uint64 poolId,
        bytes16 trancheId,
        string memory tokenName,
        string memory tokenSymbol,
        uint8 decimals,
        uint128 latestPrice
    ) public onlyGateway {
        Pool storage pool = pools[poolId];
        require(pool.createdAt > 0, "InvestmentManager/invalid-pool");
        Tranche storage tranche = pool.tranches[trancheId];
        require(tranche.createdAt == 0, "InvestmentManager/tranche-already-exists");

        tranche.poolId = poolId;
        tranche.trancheId = trancheId;
        tranche.decimals = decimals;
        tranche.tokenName = tokenName;
        tranche.tokenSymbol = tokenSymbol;
        tranche.createdAt = block.timestamp;
        tranche.latestPrice = latestPrice;

        emit TrancheAdded(poolId, trancheId);
    }

    function handleExecutedCollectInvest(
        uint64 poolId,
        bytes16 trancheId,
        address _recepient,
        uint128 currency,
        uint128 currencyInvested,
        uint128 tokensPayout
    ) public onlyGateway {
        require(currencyInvested != 0, "InvestmentManager/zero-invest");
        address _currency = tokenManager.currencyIdToAddress(currency);
        address lPool = pools[poolId].tranches[trancheId].liquidityPools[_currency];
        require(lPool != address(0), "InvestmentManager/tranche-does-not-exist");

        LPValues storage lpValues = orderbook[_recepient][lPool];
        lpValues.maxDeposit = lpValues.maxDeposit + currencyInvested;
        lpValues.maxMint = lpValues.maxMint + tokensPayout;

        LiquidityPoolLike(lPool).mint(address(escrow), tokensPayout); // mint to escrow. Recepeint can claim by calling withdraw / redeem
    }

    function handleExecutedCollectRedeem(
        uint64 poolId,
        bytes16 trancheId,
        address _recepient,
        uint128 currency,
        uint128 currencyPayout,
        uint128 trancheTokensPayout
    ) public onlyGateway {
        require(trancheTokensPayout != 0, "InvestmentManager/zero-redeem");
        address _currency = tokenManager.currencyIdToAddress(currency);
        address lPool = pools[poolId].tranches[trancheId].liquidityPools[_currency];
        require(lPool != address(0), "InvestmentManager/tranche-does-not-exist");

        LPValues storage lpValues = orderbook[_recepient][lPool];
        lpValues.maxWithdraw = lpValues.maxWithdraw + currencyPayout;
        lpValues.maxRedeem = lpValues.maxRedeem + trancheTokensPayout;

        LiquidityPoolLike(lPool).burn(address(escrow), trancheTokensPayout); // burned redeemed tokens from escrow
    }

    function handleExecutedDecreaseInvestOrder(
        uint64 poolId,
        bytes16 trancheId,
        address user,
        uint128 currency,
        uint128 currencyPayout
    ) public onlyGateway {
        require(currencyPayout != 0, "InvestmentManager/zero-payout");
        address _currency = tokenManager.currencyIdToAddress(currency);
        Pool storage pool = pools[poolId];
        LiquidityPoolLike lPool = LiquidityPoolLike(pool.tranches[trancheId].liquidityPools[_currency]);
        require(address(lPool) != address(0), "InvestmentManager/tranche-does-not-exist");
        require(pool.allowedCurrencies[_currency], "InvestmentManager/pool-currency-not-allowed");
        require(_currency != address(0), "InvestmentManager/unknown-currency");
        require(_currency == lPool.asset(), "InvestmentManager/not-tranche-currency");
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
        uint128 tokensPayout
    ) public onlyGateway {
        require(tokensPayout != 0, "InvestmentManager/zero-payout");
        address _currency = tokenManager.currencyIdToAddress(currency);
        LiquidityPoolLike lPool = LiquidityPoolLike(pools[poolId].tranches[trancheId].liquidityPools[_currency]);
        require(address(lPool) != address(0), "InvestmentManager/tranche-does-not-exist");

        require(LiquidityPoolLike(lPool).hasMember(user), "InvestmentManager/not-a-member");
        require(
            lPool.transferFrom(address(escrow), user, tokensPayout), "InvestmentManager/trancheTokens-transfer-failed"
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
            (_currencyAmount <= orderbook[user][liquidityPool].maxDeposit && _currencyAmount > 0),
            "InvestmentManager/amount-exceeds-deposit-limits"
        );

        uint128 depositPrice = calculateDepositPrice(user, liquidityPool);
        require(depositPrice > 0, "LiquidityPool/deposit-token-price-0");

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
            (_trancheTokenAmount <= orderbook[user][liquidityPool].maxMint && _trancheTokenAmount > 0),
            "InvestmentManager/amount-exceeds-mint-limits"
        );

        uint128 depositPrice = calculateDepositPrice(user, liquidityPool);
        require(depositPrice > 0, "LiquidityPool/deposit-token-price-0");

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
            (_trancheTokenAmount <= orderbook[user][liquidityPool].maxRedeem && _trancheTokenAmount > 0),
            "InvestmentManager/amount-exceeds-redeem-limits"
        );

        uint128 redeemPrice = calculateRedeemPrice(user, liquidityPool);
        require(redeemPrice > 0, "LiquidityPool/redeem-token-price-0");

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
            (_currencyAmount <= orderbook[user][liquidityPool].maxWithdraw && _currencyAmount > 0),
            "InvestmentManager/amount-exceeds-withdraw-limits"
        );

        uint128 redeemPrice = calculateRedeemPrice(user, liquidityPool);
        require(redeemPrice > 0, "LiquidityPool/redeem-token-price-0");

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
        require(
            ERC20Like(lPool.asset()).transferFrom(address(escrow), receiver, currencyAmount),
            "InvestmentManager/shares-transfer-failed"
        );
        emit RedemptionProcessed(liquidityPool, user, trancheTokenAmount);
    }

    // --- Public functions ---
    function deployTranche(uint64 poolId, bytes16 trancheId) public returns (address) {
        Tranche storage tranche = pools[poolId].tranches[trancheId];
        require(tranche.token == address(0), "InvestmentManager/tranche-already-deployed");
        require(tranche.createdAt > 0, "InvestmentManager/tranche-not-added");

        address token = trancheTokenFactory.newTrancheToken(
            poolId,
            trancheId,
            address(this),
            address(tokenManager),
            tranche.tokenName,
            tranche.tokenSymbol,
            tranche.decimals,
            tranche.latestPrice,
            tranche.createdAt
        );

        tranche.token = token;
        emit TrancheTokenDeployed(poolId, trancheId);
        return token;
    }

    function deployLiquidityPool(uint64 poolId, bytes16 trancheId, address _currency) public returns (address) {
        Tranche storage tranche = pools[poolId].tranches[trancheId];
        require(tranche.token != address(0), "InvestmentManager/tranche-does-not-exist"); // tranche must have been added
        require(_poolCurrencyCheck(poolId, _currency), "InvestmentManager/currency-not-supported"); // currency must be supported by pool

        address liquidityPool = tranche.liquidityPools[_currency];
        require(liquidityPool == address(0), "InvestmentManager/liquidityPool-already-deployed");
        require(pools[poolId].createdAt > 0, "InvestmentManager/pool-does-not-exist");

        liquidityPool =
            liquidityPoolFactory.newLiquidityPool(poolId, trancheId, _currency, tranche.token, address(this));

        tranche.liquidityPools[_currency] = liquidityPool;
        wards[liquidityPool] = 1;

        // enable LP to take the liquidity pool tokens out of escrow in case if investments
        AuthLike(tranche.token).rely(liquidityPool); // add liquidityPool as ward on tranche Token
        ERC2771Like(tranche.token).addLiquidityPool(liquidityPool);
        EscrowLike(escrow).approve(liquidityPool, address(this), type(uint256).max); // approve investment manager on tranche token for coordinating transfers
        EscrowLike(escrow).approve(liquidityPool, liquidityPool, type(uint256).max); // approve liquidityPool on tranche token to be able to burn

        emit LiquidityPoolDeployed(poolId, trancheId, liquidityPool);
        return liquidityPool;
    }

    // --- Helpers ---
    function getTrancheToken(uint64 poolId, bytes16 trancheId) public view returns (address) {
        Tranche storage tranche = pools[poolId].tranches[trancheId];
        return tranche.token;
    }

    function getLiquidityPool(uint64 poolId, bytes16 trancheId, address currency) public view returns (address) {
        return pools[poolId].tranches[trancheId].liquidityPools[currency];
    }

    function isAllowedAsPoolCurrency(uint64 poolId, address currency) public view returns (bool) {
        return pools[poolId].allowedCurrencies[currency];
    }

    function calculateDepositPrice(address user, address liquidityPool)
        public
        view
        returns (uint128 userTrancheTokenPrice)
    {
        LPValues storage lpValues = orderbook[user][liquidityPool];
        if (lpValues.maxMint == 0) {
            return 0;
        }

        (uint8 currencyDecimals, uint8 trancheTokenDecimals) = _getTokenDecimals(liquidityPool);
        userTrancheTokenPrice = _toPoolDecimals(lpValues.maxDeposit, currencyDecimals, liquidityPool)
            / _toPoolDecimals(lpValues.maxMint, trancheTokenDecimals, liquidityPool);
    }

    function calculateRedeemPrice(address user, address liquidityPool)
        public
        view
        returns (uint128 userTrancheTokenPrice)
    {
        LPValues storage lpValues = orderbook[user][liquidityPool];
        if (lpValues.maxRedeem == 0) {
            return 0;
        }

        (uint8 currencyDecimals, uint8 trancheTokenDecimals) = _getTokenDecimals(liquidityPool);
        userTrancheTokenPrice = _toPoolDecimals(lpValues.maxWithdraw, currencyDecimals, liquidityPool)
            / _toPoolDecimals(lpValues.maxRedeem, trancheTokenDecimals, liquidityPool);
    }

    function _poolCurrencyCheck(uint64 poolId, address currencyAddress) internal view returns (bool) {
        uint128 currency = tokenManager.currencyAddressToId(currencyAddress);
        require(currency != 0, "InvestmentManager/unknown-currency"); // currency index on the centrifuge chain side should start at 1
        require(pools[poolId].allowedCurrencies[currencyAddress], "InvestmentManager/pool-currency-not-allowed");
        return true;
    }

    function _liquidityPoolTokensCheck(uint64 poolId, bytes16 trancheId, address _currency, address user)
        internal
        returns (bool)
    {
        LiquidityPoolLike lPool = LiquidityPoolLike(pools[poolId].tranches[trancheId].liquidityPools[_currency]);
        require(address(lPool) != address(0), "InvestmentManager/unknown-liquidity-pool");
        require(lPool.hasMember(user), "InvestmentManager/not-a-member");
        return true;
    }

    function _calculateTrancheTokenAmount(uint128 currencyAmount, address liquidityPool, uint128 price)
        internal
        view
        returns (uint128 trancheTokenAmount)
    {
        (uint8 currencyDecimals, uint8 trancheTokenDecimals) = _getTokenDecimals(liquidityPool);
        trancheTokenAmount = _fromPoolDecimals(
            (_toPoolDecimals(currencyAmount, currencyDecimals, liquidityPool) / price),
            trancheTokenDecimals,
            liquidityPool
        );
    }

    function _calculateCurrencyAmount(uint128 trancheTokenAmount, address liquidityPool, uint128 price)
        internal
        view
        returns (uint128 currencyAmount)
    {
        (uint8 currencyDecimals, uint8 trancheTokenDecimals) = _getTokenDecimals(liquidityPool);
        currencyAmount = _fromPoolDecimals(
            (_toPoolDecimals(trancheTokenAmount, trancheTokenDecimals, liquidityPool) / price),
            currencyDecimals,
            liquidityPool
        );
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
        uint8 maxDecimals = _getPoolDecimals(liquidityPool);
        if (maxDecimals == decimals) return _value;
        return _toUint128(_value * 10 ** (maxDecimals - decimals));
    }

    /// @dev convert decimals of the value from the pool decimals back to the intended decimals
    function _fromPoolDecimals(uint128 _value, uint8 decimals, address liquidityPool)
        internal
        view
        returns (uint128 value)
    {
        uint8 maxDecimals = _getPoolDecimals(liquidityPool);
        if (maxDecimals == decimals) return _value;
        return _toUint128(_value / 10 ** (maxDecimals - decimals));
    }

    /// @dev pool decimals are the max of the currency decimals and the tranche token decimals
    function _getPoolDecimals(address liquidityPool) internal view returns (uint8 poolDecimals) {
        (uint8 currencyDecimals, uint8 trancheTokenDecimals) = _getTokenDecimals(liquidityPool);
        return uint8(Math.max(currencyDecimals, trancheTokenDecimals));
    }

    function _getTokenDecimals(address liquidityPool)
        internal
        view
        returns (uint8 currencyDecimals, uint8 trancheTokenDecimals)
    {
        currencyDecimals = ERC20Like(LiquidityPoolLike(liquidityPool).asset()).decimals();
        trancheTokenDecimals = LiquidityPoolLike(liquidityPool).decimals();
    }
}
