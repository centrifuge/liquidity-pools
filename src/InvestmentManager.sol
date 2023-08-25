// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.18;
pragma abicoder v2;

import {TrancheTokenFactoryLike, LiquidityPoolFactoryLike, MemberlistFactoryLike} from "./liquidityPool/Factory.sol";
import {MemberlistLike} from "./token/Memberlist.sol";
import "./auth/auth.sol";

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
    // 4626 functions
    function asset() external returns (address);
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
}

interface EscrowLike {
    function approve(address token, address spender, uint256 value) external;
}

interface AuthLike {
    function rely(address usr) external;
}

/// @dev centrifuge chain pool
struct Pool {
    uint64 poolId;
    uint256 createdAt;
    bool isActive;
}

/// @dev centrifuge chain tranche
struct Tranche {
    address token;
    uint64 poolId;
    bytes16 trancheId;
    // important: the decimals of the leading pool currency. Liquidity Pool shares have to be denomatimated with the same precision.
    uint8 decimals;
    uint256 createdAt;
    string tokenName;
    string tokenSymbol;
}

/// @dev liquidity pool orders and deposit/redemption limits per user
struct LPValues {
    uint128 maxDeposit;
    uint128 maxMint;
    uint128 maxWithdraw;
    uint128 maxRedeem;
}

contract InvestmentManager is Auth {
    mapping(uint64 => Pool) public pools; // pools on centrifuge chain
    mapping(uint64 => mapping(bytes16 => Tranche)) public tranches; // centrifuge chain tranches
    mapping(uint64 => mapping(bytes16 => mapping(address => address))) public liquidityPools; // evm liquidity pools - pool & tranche & currency -> liquidity pool address
    mapping(address => mapping(address => LPValues)) public orderbook; // liquidity pool orders & limits per user
    mapping(uint64 => mapping(address => bool)) public allowedPoolCurrencies; // supported currencies per pool

    GatewayLike public gateway;
    TokenManagerLike public tokenManager;
    EscrowLike public immutable escrow;

    // factories for liquidity pool deployments
    LiquidityPoolFactoryLike public immutable liquidityPoolFactory;
    TrancheTokenFactoryLike public immutable trancheTokenFactory;
    MemberlistFactoryLike public immutable memberlistFactory;

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

    constructor(
        address escrow_,
        address liquidityPoolFactory_,
        address trancheTokenFactory_,
        address memberlistFactory_
    ) {
        escrow = EscrowLike(escrow_);
        liquidityPoolFactory = LiquidityPoolFactoryLike(liquidityPoolFactory_);
        trancheTokenFactory = TrancheTokenFactoryLike(trancheTokenFactory_);
        memberlistFactory = MemberlistFactoryLike(memberlistFactory_);

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
    /// @dev request tranche token redemption. Liquidity pools have to request redemptions from the centrifuge chain before actual currency payouts can be done.
    /// The redemption requests are added to the order book on centrifuge chain. Once the next epoch is executed on centrifuge chain, liquidity pools can proceed with currency payouts in case their orders got fullfilled.
    /// @notice The user tranche tokens required to fullfill the redemption request have to be locked, even though the currency payout can only happen after epoch execution.
    /// This function automatically closed all the outstading investment orders for the user.
    function requestRedeem(uint256 trancheTokenAmount, address user) public auth {
        address _liquidityPool = msg.sender;
        LPValues storage lpValues = orderbook[user][_liquidityPool];
        LiquidityPoolLike liquidityPool = LiquidityPoolLike(_liquidityPool);
        uint128 _trancheTokenAmount = _toUint128(trancheTokenAmount);

        // check if liquidity pool currency is supported by the centrifuge pool
        require(
            _poolCurrencyCheck(liquidityPool.poolId(), liquidityPool.asset()),
            "InvestmentManager/currency-not-supported"
        );
        // check if user is allowed to hold the restriced liquidity pool tokens
        require(
            _liquidityPoolTokensCheck(liquidityPool.poolId(), liquidityPool.trancheId(), liquidityPool.asset(), user),
            "InvestmentManager/tranche-tokens-not-supported"
        );

        // todo: cancel outstanding order
        //    gateway.decreaseInvestOrder(liquidityPool.poolId(), liquidityPool.trancheId(), user, tokenManager.currencyAddressToId(liquidityPool.asset()), lpValues.openInvest);
        // }

        if (_trancheTokenAmount == 0) {
            // case: outstanding deposit orders only needed to be cancelled
            return;
        }

        if (lpValues.maxMint >= _trancheTokenAmount) {
            // case: user has unclaimed trancheTokens in escrow -> more than redemption request
            uint128 userTrancheTokenPrice = calcDepositPrice(user, _liquidityPool);
            uint128 currencyAmount = _trancheTokenAmount * userTrancheTokenPrice;
            _decreaseDepositLimits(user, _liquidityPool, currencyAmount, _trancheTokenAmount);
        } else {
            uint256 transferAmount = _trancheTokenAmount - lpValues.maxMint;
            lpValues.maxDeposit = 0;
            lpValues.maxMint = 0;

            // transfer the differene between required and locked tranche tokens from user to escrow
            require(
                liquidityPool.balanceOf(user) >= transferAmount, "InvestmentManager/insufficient-tranche-token-balance"
            );
            require(
                liquidityPool.transferFrom(user, address(escrow), transferAmount),
                "InvestmentManager/tranche-token-transfer-failed"
            );
        }
        gateway.increaseRedeemOrder(
            liquidityPool.poolId(),
            liquidityPool.trancheId(),
            user,
            tokenManager.currencyAddressToId(liquidityPool.asset()),
            _trancheTokenAmount
        );
    }

    /// @dev request tranche token redemption. Liquidity pools have to request investments from the centrifuge chain before actual tranche token payouts can be done.
    /// The deposit requests are added to the order book on centrifuge chain. Once the next epoch is executed on centrifuge chain, liquidity pools can proceed with tranche token payouts in case their orders got fullfilled.
    /// @notice The user currency amount equired to fullfill the deposit request have to be locked, even though the tranche token payout can only happen after epoch execution.
    /// This function automatically closed all the outstading redemption orders for the user.
    function requestDeposit(uint256 currencyAmount, address user) public auth {
        address _liquidityPool = msg.sender;
        LPValues storage lpValues = orderbook[user][_liquidityPool];
        LiquidityPoolLike liquidityPool = LiquidityPoolLike(_liquidityPool);
        address currency = liquidityPool.asset();
        uint128 _currencyAmount = _toUint128(currencyAmount);

        // check if liquidity pool currency is supported by the centrifuge pool
        require(_poolCurrencyCheck(liquidityPool.poolId(), currency), "InvestmentManager/currency-not-supported");
        // check if user is allowed to hold the restriced liquidity pool tokens
        require(
            _liquidityPoolTokensCheck(liquidityPool.poolId(), liquidityPool.trancheId(), currency, user),
            "InvestmentManager/tranche-tokens-not-supported"
        );

        // todo: cancel outstanding order
        //    gateway.decreaseRedeemOrder(liquidityPool.poolId(), liquidityPool.trancheId(), user, tokenManager.currencyAddressToId(liquidityPool.asset()), lpValues.openRedeem);

        if (_currencyAmount == 0) {
            // case: outstanding redemption orders only needed to be cancelled
            return;
        }
        if (lpValues.maxWithdraw >= _currencyAmount) {
            // case: user has some claimable funds in escrow -> funds > depositRequest _currencyAmount
            uint128 userTrancheTokenPrice = calcRedeemTokenPrice(user, _liquidityPool);
            uint128 trancheTokens = _currencyAmount / userTrancheTokenPrice;
            _decreaseRedemptionLimits(user, _liquidityPool, _currencyAmount, trancheTokens);
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
            liquidityPool.poolId(),
            liquidityPool.trancheId(),
            user,
            tokenManager.currencyAddressToId(liquidityPool.asset()),
            _currencyAmount
        );
    }

    function collectInvest(uint64 poolId, bytes16 trancheId, address user, address _currency) public auth {
        LiquidityPoolLike liquidityPool = LiquidityPoolLike(msg.sender);
        require(liquidityPool.hasMember(user), "InvestmentManager/not-a-member");
        require(_poolCurrencyCheck(poolId, _currency), "InvestmentManager/currency-not-supported");
        gateway.collectInvest(poolId, trancheId, user, tokenManager.currencyAddressToId(_currency));
    }

    function collectRedeem(uint64 poolId, bytes16 trancheId, address user, address _currency) public auth {
        LiquidityPoolLike liquidityPool = LiquidityPoolLike(msg.sender);
        require(liquidityPool.hasMember(user), "InvestmentManager/not-a-member");
        require(_poolCurrencyCheck(poolId, _currency), "InvestmentManager/currency-not-supported");
        gateway.collectRedeem(poolId, trancheId, user, tokenManager.currencyAddressToId(_currency));
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

        allowedPoolCurrencies[poolId][currencyAddress] = true;
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
        uint128
    ) public onlyGateway {
        Pool storage pool = pools[poolId];
        require(pool.createdAt > 0, "InvestmentManager/invalid-pool");
        Tranche storage tranche = tranches[poolId][trancheId];
        require(tranche.createdAt == 0, "InvestmentManager/tranche-already-exists");

        tranche.poolId = poolId;
        tranche.trancheId = trancheId;
        tranche.decimals = decimals;
        tranche.tokenName = tokenName;
        tranche.tokenSymbol = tokenSymbol;
        tranche.createdAt = block.timestamp;

        emit TrancheAdded(poolId, trancheId);
    }

    function handleExecutedCollectInvest(
        uint64 poolId,
        bytes16 trancheId,
        address recipient,
        uint128 currency,
        uint128 currencyInvested,
        uint128 tokensPayout
    ) public onlyGateway {
        require(currencyInvested != 0, "InvestmentManager/zero-invest");
        address currencyAddress = tokenManager.currencyIdToAddress(currency);
        address liquidityPool = liquidityPools[poolId][trancheId][currencyAddress];
        require(liquidityPool != address(0), "InvestmentManager/tranche-does-not-exist");

        LPValues storage values = orderbook[recipient][liquidityPool];
        values.maxDeposit = values.maxDeposit + currencyInvested;
        values.maxMint = values.maxMint + tokensPayout;

        LiquidityPoolLike(liquidityPool).mint(address(escrow), tokensPayout); // mint to escrow. Recepeint can claim by calling withdraw / redeem
    }

    function handleExecutedCollectRedeem(
        uint64 poolId,
        bytes16 trancheId,
        address recipient,
        uint128 currency,
        uint128 currencyPayout,
        uint128 trancheTokensRedeemed
    ) public onlyGateway {
        require(trancheTokensRedeemed != 0, "InvestmentManager/zero-redeem");
        address currencyAddress = tokenManager.currencyIdToAddress(currency);
        address liquidityPool = liquidityPools[poolId][trancheId][currencyAddress];
        require(liquidityPool != address(0), "InvestmentManager/tranche-does-not-exist");

        LPValues storage values = orderbook[recipient][liquidityPool];
        values.maxWithdraw = values.maxWithdraw + currencyPayout;
        values.maxRedeem = values.maxRedeem + trancheTokensRedeemed;

        LiquidityPoolLike(liquidityPool).burn(address(escrow), trancheTokensRedeemed); // burned redeemed tokens from escrow
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
        LiquidityPoolLike liquidityPool = LiquidityPoolLike(liquidityPools[poolId][trancheId][_currency]);
        require(address(liquidityPool) != address(0), "InvestmentManager/tranche-does-not-exist");
        require(allowedPoolCurrencies[poolId][_currency], "InvestmentManager/pool-currency-not-allowed");
        require(_currency != address(0), "InvestmentManager/unknown-currency");
        require(_currency == liquidityPool.asset(), "InvestmentManager/not-tranche-currency");
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
        LiquidityPoolLike liquidityPool = LiquidityPoolLike(liquidityPools[poolId][trancheId][_currency]);
        require(address(liquidityPool) != address(0), "InvestmentManager/tranche-does-not-exist");

        require(LiquidityPoolLike(liquidityPool).hasMember(user), "InvestmentManager/not-a-member");
        require(
            liquidityPool.transferFrom(address(escrow), user, tokensPayout),
            "InvestmentManager/trancheTokens-transfer-failed"
        );
    }

    // --- Liquidity Pool Function ---

    /// @return currencyAmount is type of uin256 to support the EIP4626 Liquidity Pool interface
    function maxDeposit(address user, address _liquidityPool) public view returns (uint256 currencyAmount) {
        currencyAmount = uint256(orderbook[user][_liquidityPool].maxDeposit);
    }

    /// @return trancheTokenAmount type of uin256 to support the EIP4626 Liquidity Pool interface
    function maxMint(address user, address _liquidityPool) public view returns (uint256 trancheTokenAmount) {
        trancheTokenAmount = uint256(orderbook[user][_liquidityPool].maxMint);
    }

    /// @return currencyAmount type of uin256 to support the EIP4626 Liquidity Pool interface
    function maxWithdraw(address user, address _liquidityPool) public view returns (uint256 currencyAmount) {
        currencyAmount = uint256(orderbook[user][_liquidityPool].maxWithdraw);
    }

    /// @return trancheTokenAmount type of uin256 to support the EIP4626 Liquidity Pool interface
    function maxRedeem(address user, address _liquidityPool) public view returns (uint256 trancheTokenAmount) {
        trancheTokenAmount = uint256(orderbook[user][_liquidityPool].maxRedeem);
    }

    /// @dev processes user's currency deposit / investment after the epoch has been executed on Centrifuge chain.
    /// In case user's invest order was fullfilled on Centrifuge chain during epoch execution MaxDeposit and MaxMint are increased and trancheTokens can be transferred to user's wallet on calling processDeposit.
    /// Note: The currency required to fullfill the invest order is already locked in escrow upon calling requestDeposit.
    /// @notice trancheTokenAmount return value is type of uint256 to be compliant with EIP4626 LiquidityPool interface
    /// @return trancheTokenAmount the amount of trancheTokens transferred to the user's wallet after successful depoit
    function processDeposit(address user, uint256 currencyAmount) public auth returns (uint256 trancheTokenAmount) {
        address _liquidityPool = msg.sender;
        uint128 _currencyAmount = _toUint128(currencyAmount);
        require(
            (_currencyAmount <= orderbook[user][_liquidityPool].maxDeposit && _currencyAmount > 0),
            "InvestmentManager/amount-exceeds-deposit-limits"
        );
        (trancheTokenAmount,) = _deposit(0, _currencyAmount, _liquidityPool, user);
    }

    /// @dev processes user's currency deposit / investment after the epoch has been executed on Centrifuge chain.
    /// In case user's invest order was fullfilled on Centrifuge chain during epoch execution MaxDeposit and MaxMint are increased and trancheTokens can be transferred to user's wallet on calling processDeposit or processMint.
    /// Note: The currency amount required to fullfill the invest order is already locked in escrow upon calling requestDeposit.
    /// Note: The tranche tokens are already minted on collectInvest and are deposited to the escrow account until the users calls mint, or deposit.
    /// @notice currencyAmount return value is type of uint256 to be compliant with EIP4626 LiquidityPool interface
    /// @return currencyAmount the amount of liquidityPool assets invested and locked in escrow in order for the amount of tranche received after successful investment into the pool.
    function processMint(address user, uint256 trancheTokenAmount) public auth returns (uint256 currencyAmount) {
        address _liquidityPool = msg.sender;
        uint128 trancheTokenAmount = _toUint128(trancheTokenAmount);
        require(
            (trancheTokenAmount <= orderbook[user][_liquidityPool].maxMint && trancheTokenAmount > 0),
            "InvestmentManager/amount-exceeds-mint-limits"
        );

        (, currencyAmount) = _deposit(trancheTokenAmount, 0, _liquidityPool, user);
    }

    function _deposit(uint128 trancheTokenAmount, uint128 currencyAmount, address liquidityPool, address user)
        internal
        returns (uint128 _trancheTokenAmount, uint128 _currencyAmount)
    {
        LiquidityPoolLike _liquidityPool = LiquidityPoolLike(liquidityPool);
        uint128 depositPrice = calcDepositPrice(user, liquidityPool);
        require((depositPrice > 0), "LiquidityPool/deposit-token-price-0");

        if (currencyAmount == 0) {
            currencyAmount = trancheTokenAmount * depositPrice;
            trancheTokenAmount = trancheTokenAmount;
        } else {
            trancheTokenAmount = currencyAmount / depositPrice;
            currencyAmount = currencyAmount;
        }

        _decreaseDepositLimits(user, liquidityPool, currencyAmount, trancheTokenAmount); // decrease the possible deposit limits
        require(_liquidityPool.hasMember(user), "InvestmentManager/trancheTokens-not-a-member");
        require(
            _liquidityPool.transferFrom(address(escrow), user, trancheTokenAmount),
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
        (, currencyAmount) = _redeem(_trancheTokenAmount, 0, liquidityPool, receiver, user);
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
        (trancheTokenAmount,) = _redeem(0, _currencyAmount, liquidityPool, receiver, user);
    }

    function _redeem(
        uint128 trancheTokenAmount,
        uint128 currencyAmount,
        address liquidityPool,
        address receiver,
        address user
    ) internal returns (uint128 _trancheTokenAmount, uint128 _currencyAmount) {
        LiquidityPoolLike _liquidityPool = LiquidityPoolLike(liquidityPool);
        uint128 redeemPrice = calcRedeemTokenPrice(user, liquidityPool);
        require((redeemPrice > 0), "LiquidityPool/redeem-token-price-0");

        if (currencyAmount == 0) {
            _currencyAmount = trancheTokenAmount * redeemPrice;
            _trancheTokenAmount = trancheTokenAmount;
        } else {
            _trancheTokenAmount = currencyAmount / redeemPrice;
            _currencyAmount = currencyAmount;
        }

        _decreaseRedemptionLimits(user, liquidityPool, _currencyAmount, _trancheTokenAmount); // decrease the possible deposit limits
        require(
            ERC20Like(_liquidityPool.asset()).transferFrom(address(escrow), receiver, currencyAmount),
            "InvestmentManager/shares-transfer-failed"
        );
        emit RedemptionProcessed(liquidityPool, user, trancheTokenAmount);
    }

    // ----- public functions
    function deployLiquidityPool(uint64 poolId, bytes16 trancheId, address currency) public returns (address) {
        address liquidityPool = liquidityPools[poolId][trancheId][currency];
        require(liquidityPool == address(0), "InvestmentManager/liquidityPool-already-deployed");
        require(pools[poolId].createdAt > 0, "InvestmentManager/pool-does-not-exist");
        Tranche storage tranche = tranches[poolId][trancheId];
        require(tranche.token != address(0), "InvestmentManager/tranche-does-not-exist"); // tranche must have been added
        require(_poolCurrencyCheck(poolId, currency), "InvestmentManager/currency-not-supported"); // currency must be supported by pool
        uint128 currencyId = tokenManager.currencyAddressToId(currency);

        liquidityPool = liquidityPoolFactory.newLiquidityPool(
            poolId, trancheId, currencyId, currency, tranche.token, address(this), address(gateway)
        );

        EscrowLike(escrow).approve(tranche.token, liquidityPool, type(uint256).max);
        liquidityPools[poolId][trancheId][currency] = liquidityPool;
        wards[liquidityPool] = 1;
        // enable connectors to take the liquidity pool tokens out of escrow in case if investments
        AuthLike(tranche.token).rely(liquidityPool); // add liquidityPool as ward on tranche Token

        emit LiquidityPoolDeployed(poolId, trancheId, liquidityPool);
        return liquidityPool;
    }

    function deployTranche(uint64 poolId, bytes16 trancheId) public returns (address) {
        Tranche storage tranche = tranches[poolId][trancheId];
        require(tranche.token == address(0), "InvestmentManager/tranche-already-deployed");
        require(tranche.createdAt > 0, "InvestmentManager/tranche-not-added");
        // deploy liquidity pool set gateway as admin on liquidityPool & memberlist
        address memberlist = memberlistFactory.newMemberlist(address(gateway), address(this));
        AuthLike(memberlist).rely(address(tokenManager));
        MemberlistLike(memberlist).updateMember(address(escrow), type(uint256).max); // add escrow to tranche tokens memberlist

        address token = trancheTokenFactory.newTrancheToken(
            poolId,
            trancheId,
            address(this),
            memberlist,
            tranche.tokenName,
            tranche.tokenSymbol,
            tranche.decimals,
            address(gateway)
        );
        AuthLike(token).rely(address(tokenManager)); // to be able to mint for incoming transfers

        tranche.token = token;
        emit TrancheTokenDeployed(poolId, trancheId);
        return token;
    }

    // ------ helper functions
    function getTrancheToken(uint64 poolId, bytes16 trancheId) public view returns (address) {
        Tranche storage tranche = tranches[poolId][trancheId];
        return tranche.token;
    }

    // TODO: check rounding
    function calcDepositPrice(address user, address liquidityPool)
        public
        view
        returns (uint128 userTrancheTokenPrice)
    {
        LPValues storage lpValues = orderbook[user][liquidityPool];
        if (lpValues.maxMint == 0) {
            return 0;
        }
        userTrancheTokenPrice = lpValues.maxDeposit / lpValues.maxMint;
    }

    function calcRedeemTokenPrice(address user, address liquidityPool)
        public
        view
        returns (uint128 userTrancheTokenPrice)
    {
        LPValues storage lpValues = orderbook[user][liquidityPool];
        if (lpValues.maxRedeem == 0) {
            return 0;
        }
        userTrancheTokenPrice = lpValues.maxWithdraw / lpValues.maxRedeem;
    }

    function _poolCurrencyCheck(uint64 poolId, address currencyAddress) internal view returns (bool) {
        uint128 currency = tokenManager.currencyAddressToId(currencyAddress);
        require(currency != 0, "InvestmentManager/unknown-currency"); // currency index on the centrifuge chain side should start at 1
        require(allowedPoolCurrencies[poolId][currencyAddress], "InvestmentManager/pool-currency-not-allowed");
        return true;
    }

    function _liquidityPoolTokensCheck(uint64 poolId, bytes16 trancheId, address currency, address user)
        internal
        returns (bool)
    {
        LiquidityPoolLike liquidityPool = LiquidityPoolLike(liquidityPools[poolId][trancheId][currency]);
        require(address(liquidityPool) != address(0), "InvestmentManager/unknown-liquidity-pool");
        require(liquidityPool.hasMember(user), "InvestmentManager/not-a-member");
        return true;
    }

    function _decreaseDepositLimits(address user, address liquidityPool, uint128 currency, uint128 trancheTokens)
        internal
    {
        LPValues storage values = orderbook[user][liquidityPool];
        if (values.maxDeposit < currency) {
            values.maxDeposit = 0;
        } else {
            values.maxDeposit = values.maxDeposit - currency;
        }
        if (values.maxMint < trancheTokens) {
            values.maxMint = 0;
        } else {
            values.maxMint = values.maxMint - trancheTokens;
        }
    }

    function _decreaseRedemptionLimits(address user, address liquidityPool, uint128 currency, uint128 trancheTokens)
        internal
    {
        LPValues storage values = orderbook[user][liquidityPool];
        if (values.maxWithdraw < currency) {
            values.maxWithdraw = 0;
        } else {
            values.maxWithdraw = values.maxWithdraw - currency;
        }
        if (values.maxRedeem < trancheTokens) {
            values.maxRedeem = 0;
        } else {
            values.maxRedeem = values.maxRedeem - trancheTokens;
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
}
