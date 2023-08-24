// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.18;
pragma abicoder v2;

import {TrancheTokenFactoryLike, LiquidityPoolFactoryLike, MemberlistFactoryLike} from "./liquidityPool/Factory.sol";
import {MemberlistLike} from "./token/Memberlist.sol";
import "./auth/auth.sol";

interface GatewayLike {
    function transferTrancheTokensToCentrifuge(
        uint64 poolId,
        bytes16 trancheId,
        address sender,
        bytes32 destinationAddress,
        uint128 amount
    ) external;
    function transferTrancheTokensToEVM(
        uint64 poolId,
        bytes16 trancheId,
        address sender,
        uint64 destinationChainId,
        uint128 currencyId,
        address destinationAddress,
        uint128 amount
    ) external;
    function transfer(uint128 currency, address sender, bytes32 recipient, uint128 amount) external;
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
    function paused() external returns (bool);
}

interface LiquidityPoolLike {
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

interface TrancheTokenLike {
    function updateTokenPrice(uint128 _tokenPrice) external;
    function memberlist() external returns (address);
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

    mapping(uint128 => address) public currencyIdToAddress; // chain agnostic currency id -> evm currency address
    mapping(address => uint128) public currencyAddressToId; // The reverse mapping of `currencyIdToAddress`
    mapping(uint64 => mapping(address => bool)) public allowedPoolCurrencies; // supported currencies per pool

    GatewayLike public gateway;
    EscrowLike public immutable escrow;

    // factories for liquidity pool deployments
    LiquidityPoolFactoryLike public immutable liquidityPoolFactory;
    TrancheTokenFactoryLike public immutable trancheTokenFactory;
    MemberlistFactoryLike public immutable memberlistFactory;

    uint256 constant MAX_UINT256 = type(uint256).max;
    uint128 constant MAX_UINT128 = type(uint128).max;

    // --- Events ---
    event File(bytes32 indexed what, address data);
    event CurrencyAdded(uint128 indexed currency, address indexed currencyAddress);
    event PoolAdded(uint64 indexed poolId);
    event PoolCurrencyAllowed(uint128 indexed currency, uint64 indexed poolId);
    event TrancheAdded(uint64 indexed poolId, bytes16 indexed trancheId);
    event TrancheDeployed(uint64 indexed poolId, bytes16 indexed trancheId, address indexed token);
    event DepositProcessed(address indexed liquidityPool, address indexed user, uint128 indexed currencyAmount);
    event RedemptionProcessed(address indexed liquidityPool, address indexed user, uint128 indexed trancheTokenAmount);
    event LiquidityPoolDeployed(uint64 indexed poolId, bytes16 indexed trancheId, address indexed liquidityPoool);
    event TrancheTokenDeployed(uint64 indexed poolId, bytes16 indexed trancheId);

    constructor(address escrow_, address liquidityPoolFactory_, address trancheTokenFactory_, address memberlistFactory_) {
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
        else revert("InvestmentManager/file-unrecognized-param");
        emit File(what, data);
    }

    // --- liquidity pool outgoing message handling ---
    /// @dev request tranche token redemption. Liquidity pools have to request redemptions from the centrifuge chain before actual currency payouts can be done.
    /// The redemption requests are added to the order book on centrifuge chain. Once the next epoch is executed on centrifuge chain, liquidity pools can proceed with currency payouts in case their orders got fullfilled.
    /// @notice The user tranche tokens required to fullfill the redemption request have to be locked, even though the currency payout can only happen after epoch execution.
    /// This function automatically closed all the outstading investment orders for the user.
    function requestRedeem(uint256 _trancheTokenAmount, address _user) public auth {
        address _liquidityPool = msg.sender;
        LPValues storage lpValues = orderbook[_user][_liquidityPool];
        LiquidityPoolLike lPool = LiquidityPoolLike(_liquidityPool);
        uint128 trancheTokenAmount = _toUint128(_trancheTokenAmount);

        // check if liquidity pool currency is supported by the centrifuge pool
        require(_poolCurrencyCheck(lPool.poolId(), lPool.asset()), "InvestmentManager/currency-not-supported");
        // check if user is allowed to hold the restriced liquidity pool tokens
        require(
            _liquidityPoolTokensCheck(lPool.poolId(), lPool.trancheId(), lPool.asset(), _user),
            "InvestmentManager/tranche-tokens-not-supported"
        );

        // todo: cancel outstanding order
        //    gateway.decreaseInvestOrder(lPool.poolId(), lPool.trancheId(), _user, currencyAddressToId[lPool.asset()], lpValues.openInvest);
        // }

        if (trancheTokenAmount == 0) {
            // case: outstanding deposit orders only needed to be cancelled
            return;
        }

        if (lpValues.maxMint >= trancheTokenAmount) {
            // case: user has unclaimed trancheTokens in escrow -> more than redemption request
            uint128 userTrancheTokenPrice = calcDepositPrice(_user, _liquidityPool);
            uint128 currencyAmount = trancheTokenAmount * userTrancheTokenPrice;
            _decreaseDepositLimits(_user, _liquidityPool, currencyAmount, trancheTokenAmount);
        } else {
            uint256 transferAmount = trancheTokenAmount - lpValues.maxMint;
            lpValues.maxDeposit = 0;
            lpValues.maxMint = 0;

            // transfer the differene between required and locked tranche tokens from user to escrow
            require(lPool.balanceOf(_user) >= transferAmount, "InvestmentManager/insufficient-tranche-token-balance");
            require(
                lPool.transferFrom(_user, address(escrow), transferAmount),
                "InvestmentManager/tranche-token-transfer-failed"
            );
        }
        gateway.increaseRedeemOrder(
            lPool.poolId(), lPool.trancheId(), _user, currencyAddressToId[lPool.asset()], trancheTokenAmount
        );
    }

    /// @dev request tranche token redemption. Liquidity pools have to request investments from the centrifuge chain before actual tranche token payouts can be done.
    /// The deposit requests are added to the order book on centrifuge chain. Once the next epoch is executed on centrifuge chain, liquidity pools can proceed with tranche token payouts in case their orders got fullfilled.
    /// @notice The user currency amount equired to fullfill the deposit request have to be locked, even though the tranche token payout can only happen after epoch execution.
    /// This function automatically closed all the outstading redemption orders for the user.
    function requestDeposit(uint256 _currencyAmount, address _user) public auth {
        address _liquidityPool = msg.sender;
        LPValues storage lpValues = orderbook[_user][_liquidityPool];
        LiquidityPoolLike lPool = LiquidityPoolLike(_liquidityPool);
        address currency = lPool.asset();
        uint128 currencyAmount = _toUint128(_currencyAmount);

        // check if liquidity pool currency is supported by the centrifuge pool
        require(_poolCurrencyCheck(lPool.poolId(), currency), "InvestmentManager/currency-not-supported");
        // check if user is allowed to hold the restriced liquidity pool tokens
        require(
            _liquidityPoolTokensCheck(lPool.poolId(), lPool.trancheId(), currency, _user),
            "InvestmentManager/tranche-tokens-not-supported"
        );

        // todo: cancel outstanding order
        //    gateway.decreaseRedeemOrder(lPool.poolId(), lPool.trancheId(), _user, currencyAddressToId[lPool.asset()], lpValues.openRedeem);

        if (currencyAmount == 0) {
            // case: outstanding redemption orders only needed to be cancelled
            return;
        }
        if (lpValues.maxWithdraw >= currencyAmount) {
            // case: user has some claimable funds in escrow -> funds > depositRequest currencyAmount
            uint128 userTrancheTokenPrice = calcRedeemTokenPrice(_user, _liquidityPool);
            uint128 trancheTokens = currencyAmount / userTrancheTokenPrice;
            _decreaseRedemptionLimits(_user, _liquidityPool, currencyAmount, trancheTokens);
        } else {
            uint128 transferAmount = currencyAmount - lpValues.maxWithdraw;
            lpValues.maxWithdraw = 0;
            lpValues.maxRedeem = 0;

            // transfer the differene between required and locked currency from user to escrow
            require(ERC20Like(currency).balanceOf(_user) >= transferAmount, "InvestmentManager/insufficient-balance");
            require(
                ERC20Like(currency).transferFrom(_user, address(escrow), transferAmount),
                "InvestmentManager/currency-transfer-failed"
            );
        }
        gateway.increaseInvestOrder(
            lPool.poolId(), lPool.trancheId(), _user, currencyAddressToId[currency], currencyAmount
        );
    }

    function collectInvest(uint64 _poolId, bytes16 _trancheId, address _user, address _currency) public auth {
        LiquidityPoolLike lPool = LiquidityPoolLike(msg.sender);
        require(lPool.hasMember(_user), "InvestmentManager/not-a-member");
        require(_poolCurrencyCheck(_poolId, _currency), "InvestmentManager/currency-not-supported");
        gateway.collectInvest(_poolId, _trancheId, _user, currencyAddressToId[_currency]);
    }

    function collectRedeem(uint64 _poolId, bytes16 _trancheId, address _user, address _currency) public auth {
        LiquidityPoolLike lPool = LiquidityPoolLike(msg.sender);
        require(lPool.hasMember(_user), "InvestmentManager/not-a-member");
        require(_poolCurrencyCheck(_poolId, _currency), "InvestmentManager/currency-not-supported");
        gateway.collectRedeem(_poolId, _trancheId, _user, currencyAddressToId[_currency]);
    }

    // --- Incoming message handling ---
    /// @dev a global chain agnostic currency index is maintained on centrifuge chain. This function maps a currency from the centrifuge chain index to its corresponding address on the evm chain.
    /// The chain agnostic currency id has to be used to pass currency information to the centrifuge chain.
    /// @notice this function can only be executed by the gateway contract.
    function addCurrency(uint128 currency, address currencyAddress) public onlyGateway {
        // currency index on the centrifuge chain side should start at 1
        require(currency > 0, "InvestmentManager/currency-id-has-to-be-greater-than-0");
        require(currencyIdToAddress[currency] == address(0), "InvestmentManager/currency-id-in-use");
        require(currencyAddressToId[currencyAddress] == 0, "InvestmentManager/currency-address-in-use");

        currencyIdToAddress[currency] = currencyAddress;
        currencyAddressToId[currencyAddress] = currency;

        // enable connectors to take the currency out of escrow in case of redemptions
        EscrowLike(escrow).approve(currencyAddress, address(this), MAX_UINT256);
        emit CurrencyAdded(currency, currencyAddress);
    }

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

        address currencyAddress = currencyIdToAddress[currency];
        require(currencyAddress != address(0), "InvestmentManager/unknown-currency");

        allowedPoolCurrencies[poolId][currencyAddress] = true;
        emit PoolCurrencyAllowed(currency, poolId);
    }

    /// @dev new tranche details from an existng centrifuge chain pool are added.
    /// @notice the function can only be executed by the gateway contract.
    function addTranche(
        uint64 _poolId,
        bytes16 _trancheId,
        string memory _tokenName,
        string memory _tokenSymbol,
        uint8 _decimals,
        uint128 _price // not required here
    ) public onlyGateway {
        Pool storage pool = pools[_poolId];
        require(pool.createdAt > 0, "InvestmentManager/invalid-pool");
        Tranche storage tranche = tranches[_poolId][_trancheId];
        require(tranche.createdAt == 0, "InvestmentManager/tranche-already-exists");

        tranche.poolId = _poolId;
        tranche.trancheId = _trancheId;
        tranche.decimals = _decimals;
        tranche.tokenName = _tokenName;
        tranche.tokenSymbol = _tokenSymbol;
        tranche.createdAt = block.timestamp;

        emit TrancheAdded(_poolId, _trancheId);
    }

    function updateTokenPrice(uint64 _poolId, bytes16 _trancheId, uint128 _price) public onlyGateway {
        Tranche storage tranche = tranches[_poolId][_trancheId];
        require(tranche.token != address(0), "InvestmentManager/tranche-not-deployed");
       TrancheTokenLike(tranche.token).updateTokenPrice(_price);       
    }

    function updateMember(uint64 _poolId, bytes16 _trancheId, address _user, uint64 _validUntil) public onlyGateway {
        Tranche storage tranche = tranches[_poolId][_trancheId];
        require(tranche.token != address(0), "InvestmentManager/tranche-not-deployed");
        MemberlistLike memberlist = MemberlistLike(TrancheTokenLike(tranche.token).memberlist());
        memberlist.updateMember(_user, _validUntil);
    }

    function handleExecutedCollectInvest(
        uint64 _poolId,
        bytes16 _trancheId,
        address _recepient,
        uint128 _currency,
        uint128 _currencyInvested,
        uint128 _tokensPayout
    ) public onlyGateway {
        require(_currencyInvested != 0, "InvestmentManager/zero-invest");
        address currency = currencyIdToAddress[_currency];
        address lPool = liquidityPools[_poolId][_trancheId][currency];
        require(lPool != address(0), "InvestmentManager/tranche-does-not-exist");

        LPValues storage values = orderbook[_recepient][lPool];
        values.maxDeposit = values.maxDeposit + _currencyInvested;
        values.maxMint = values.maxMint + _tokensPayout;

        LiquidityPoolLike(lPool).mint(address(escrow), _tokensPayout); // mint to escrow. Recepeint can claim by calling withdraw / redeem
    }

    function handleExecutedCollectRedeem(
        uint64 _poolId,
        bytes16 _trancheId,
        address _recepient,
        uint128 _currency,
        uint128 _currencyPayout,
        uint128 _trancheTokensRedeemed
    ) public onlyGateway {
        require(_trancheTokensRedeemed != 0, "InvestmentManager/zero-redeem");
        address currency = currencyIdToAddress[_currency];
        address lPool = liquidityPools[_poolId][_trancheId][currency];
        require(lPool != address(0), "InvestmentManager/tranche-does-not-exist");

        LPValues storage values = orderbook[_recepient][lPool];
        values.maxWithdraw = values.maxWithdraw + _currencyPayout;
        values.maxRedeem = values.maxRedeem + _trancheTokensRedeemed;

        LiquidityPoolLike(lPool).burn(address(escrow), _trancheTokensRedeemed); // burned redeemed tokens from escrow
    }

    function handleExecutedDecreaseInvestOrder(
        uint64 _poolId,
        bytes16 _trancheId,
        address _user,
        uint128 _currency,
        uint128 _currencyPayout
    ) public onlyGateway {
        require(_currencyPayout != 0, "InvestmentManager/zero-payout");
        address currency = currencyIdToAddress[_currency];
        LiquidityPoolLike lPool = LiquidityPoolLike(liquidityPools[_poolId][_trancheId][currency]);
        require(address(lPool) != address(0), "InvestmentManager/tranche-does-not-exist");
        require(allowedPoolCurrencies[_poolId][currency], "InvestmentManager/pool-currency-not-allowed");
        require(currency != address(0), "InvestmentManager/unknown-currency");
        require(currency == lPool.asset(), "InvestmentManager/not-tranche-currency");
        require(
            ERC20Like(currency).transferFrom(address(escrow), _user, _currencyPayout),
            "InvestmentManager/currency-transfer-failed"
        );
    }

    function handleExecutedDecreaseRedeemOrder(
        uint64 _poolId,
        bytes16 _trancheId,
        address _user,
        uint128 _currency,
        uint128 _tokensPayout
    ) public onlyGateway {
        require(_tokensPayout != 0, "InvestmentManager/zero-payout");
        address currency = currencyIdToAddress[_currency];
        LiquidityPoolLike lPool = LiquidityPoolLike(liquidityPools[_poolId][_trancheId][currency]);
        require(address(lPool) != address(0), "InvestmentManager/tranche-does-not-exist");

        require(LiquidityPoolLike(lPool).hasMember(_user), "InvestmentManager/not-a-member");
        require(
            lPool.transferFrom(address(escrow), _user, _tokensPayout), "InvestmentManager/trancheTokens-transfer-failed"
        );
    }

    // --- Liquidity Pool Function ---

    /// @return currencyAmount is type of uin256 to support the EIP4626 Liquidity Pool interface
    function maxDeposit(address _user, address _liquidityPool) public view returns (uint256 currencyAmount) {
        currencyAmount = uint256(orderbook[_user][_liquidityPool].maxDeposit);
    }

    /// @return trancheTokenAmount type of uin256 to support the EIP4626 Liquidity Pool interface
    function maxMint(address _user, address _liquidityPool) public view returns (uint256 trancheTokenAmount) {
        trancheTokenAmount = uint256(orderbook[_user][_liquidityPool].maxMint);
    }

    /// @return currencyAmount type of uin256 to support the EIP4626 Liquidity Pool interface
    function maxWithdraw(address _user, address _liquidityPool) public view returns (uint256 currencyAmount) {
        currencyAmount = uint256(orderbook[_user][_liquidityPool].maxWithdraw);
    }

    /// @return trancheTokenAmount type of uin256 to support the EIP4626 Liquidity Pool interface
    function maxRedeem(address _user, address _liquidityPool) public view returns (uint256 trancheTokenAmount) {
        trancheTokenAmount = uint256(orderbook[_user][_liquidityPool].maxRedeem);
    }

    /// @dev processes user's currency deposit / investment after the epoch has been executed on Centrifuge chain.
    /// In case user's invest order was fullfilled on Centrifuge chain during epoch execution MaxDeposit and MaxMint are increased and trancheTokens can be transferred to user's wallet on calling processDeposit.
    /// Note: The currency required to fullfill the invest order is already locked in escrow upon calling requestDeposit.
    /// @notice trancheTokenAmount return value is type of uint256 to be compliant with EIP4626 LiquidityPool interface
    /// @return trancheTokenAmount the amount of trancheTokens transferred to the user's wallet after successful depoit
    function processDeposit(address _user, uint256 _currencyAmount) public auth returns (uint256 trancheTokenAmount) {
        address _liquidityPool = msg.sender;
        uint128 currencyAmount = _toUint128(_currencyAmount);
        require(
            (currencyAmount <= orderbook[_user][_liquidityPool].maxDeposit && currencyAmount > 0),
            "InvestmentManager/amount-exceeds-deposit-limits"
        );

        (trancheTokenAmount,) = _deposit(0, currencyAmount, _liquidityPool, _user);
    }

    /// @dev processes user's currency deposit / investment after the epoch has been executed on Centrifuge chain.
    /// In case user's invest order was fullfilled on Centrifuge chain during epoch execution MaxDeposit and MaxMint are increased and trancheTokens can be transferred to user's wallet on calling processDeposit or processMint.
    /// Note: The currency amount required to fullfill the invest order is already locked in escrow upon calling requestDeposit.
    /// Note: The tranche tokens are already minted on collectInvest and are deposited to the escrow account until the users calls mint, or deposit.
    /// @notice currencyAmount return value is type of uint256 to be compliant with EIP4626 LiquidityPool interface
    /// @return currencyAmount the amount of liquidityPool assets invested and locked in escrow in order for the amount of tranche received after successful investment into the pool.
    function processMint(address _user, uint256 _trancheTokenAmount) public auth returns (uint256 currencyAmount) {
        address _liquidityPool = msg.sender;
        uint128 trancheTokenAmount = _toUint128(_trancheTokenAmount);
        require(
            (trancheTokenAmount <= orderbook[_user][_liquidityPool].maxMint && trancheTokenAmount > 0),
            "InvestmentManager/amount-exceeds-mint-limits"
        );

        (, currencyAmount) = _deposit(trancheTokenAmount, 0, _liquidityPool, _user);
    }

    function _deposit(uint128 _trancheTokenAmount, uint128 _currencyAmount, address _liquidityPool, address _user)
        internal
        returns (uint128 trancheTokenAmount, uint128 currencyAmount)
    {
        LiquidityPoolLike lPool = LiquidityPoolLike(_liquidityPool);
        uint128 depositPrice = calcDepositPrice(_user, _liquidityPool);
        require((depositPrice > 0), "LiquidityPool/deposit-token-price-0");

        if (_currencyAmount == 0) {
            currencyAmount = _trancheTokenAmount * depositPrice;
            trancheTokenAmount = _trancheTokenAmount;
        } else {
            trancheTokenAmount = _currencyAmount / depositPrice;
            currencyAmount = _currencyAmount;
        }

        _decreaseDepositLimits(_user, _liquidityPool, currencyAmount, trancheTokenAmount); // decrease the possible deposit limits
        require(lPool.hasMember(_user), "InvestmentManager/trancheTokens-not-a-member");
        require(
            lPool.transferFrom(address(escrow), _user, trancheTokenAmount),
            "InvestmentManager/trancheTokens-transfer-failed"
        );

        emit DepositProcessed(_liquidityPool, _user, currencyAmount);
    }

    /// @dev processes user's trancheToken redemption after the epoch has been executed on Centrifuge chain.
    /// In case user's redempion order was fullfilled on Centrifuge chain during epoch execution MaxRedeem and MaxWithdraw are increased and LiquidityPool currency can be transferred to user's wallet on calling processRedeem or processWithdraw.
    /// Note: The trancheToken amount required to fullfill the redemption order was already locked in escrow upon calling requestRedeem and burned upon collectRedeem.
    /// @notice currencyAmount return value is type of uint256 to be compliant with EIP4626 LiquidityPool interface
    /// @return currencyAmount the amount of liquidityPool assets received for the amount of redeemed/burned trancheTokens.
    function processRedeem(uint256 _trancheTokenAmount, address _receiver, address _user)
        public
        auth
        returns (uint256 currencyAmount)
    {
        address _liquidityPool = msg.sender;
        uint128 trancheTokenAmount = _toUint128(_trancheTokenAmount);
        require(
            (trancheTokenAmount <= orderbook[_user][_liquidityPool].maxRedeem && trancheTokenAmount > 0),
            "InvestmentManager/amount-exceeds-redeem-limits"
        );
        (, currencyAmount) = _redeem(trancheTokenAmount, 0, _liquidityPool, _receiver, _user);
    }

    /// @dev processes user's trancheToken redemption after the epoch has been executed on Centrifuge chain.
    /// In case user's redempion order was fullfilled on Centrifuge chain during epoch execution MaxRedeem and MaxWithdraw are increased and LiquidityPool currency can be transferred to user's wallet on calling processRedeem or processWithdraw.
    /// Note: The trancheToken amount required to fullfill the redemption order was already locked in escrow upon calling requestRedeem and burned upon collectRedeem.
    /// @notice trancheTokenAmount return value is type of uint256 to be compliant with EIP4626 LiquidityPool interface
    /// @return trancheTokenAmount the amount of trancheTokens redeemed/burned required to receive the currencyAmount payout/withdrawel.
    function processWithdraw(uint256 _currencyAmount, address _receiver, address _user)
        public
        auth
        returns (uint256 trancheTokenAmount)
    {
        address _liquidityPool = msg.sender;
        uint128 currencyAmount = _toUint128(_currencyAmount);
        require(
            (currencyAmount <= orderbook[_user][_liquidityPool].maxWithdraw && currencyAmount > 0),
            "InvestmentManager/amount-exceeds-withdraw-limits"
        );
        (trancheTokenAmount,) = _redeem(0, currencyAmount, _liquidityPool, _receiver, _user);
    }

    function _redeem(
        uint128 _trancheTokenAmount,
        uint128 _currencyAmount,
        address _liquidityPool,
        address _receiver,
        address _user
    ) internal returns (uint128 trancheTokenAmount, uint128 currencyAmount) {
        LiquidityPoolLike lPool = LiquidityPoolLike(_liquidityPool);
        uint128 redeemPrice = calcRedeemTokenPrice(_user, _liquidityPool);
        require((redeemPrice > 0), "LiquidityPool/redeem-token-price-0");

        if (_currencyAmount == 0) {
            currencyAmount = _trancheTokenAmount * redeemPrice;
            trancheTokenAmount = _trancheTokenAmount;
        } else {
            trancheTokenAmount = _currencyAmount / redeemPrice;
            currencyAmount = _currencyAmount;
        }

        _decreaseRedemptionLimits(_user, _liquidityPool, currencyAmount, trancheTokenAmount); // decrease the possible deposit limits
        require(
            ERC20Like(lPool.asset()).transferFrom(address(escrow), _receiver, currencyAmount),
            "InvestmentManager/shares-transfer-failed"
        );
        emit RedemptionProcessed(_liquidityPool, _user, trancheTokenAmount);
    }

    // ----- public functions
    function deployLiquidityPool(uint64 _poolId, bytes16 _trancheId, address _currency) public returns (address) {
        address liquidityPool = liquidityPools[_poolId][_trancheId][_currency];
        require(liquidityPool == address(0), "InvestmentManager/liquidityPool-already-deployed");
        require(pools[_poolId].createdAt > 0, "InvestmentManager/pool-does-not-exist");
        Tranche storage tranche = tranches[_poolId][_trancheId];
        require(tranche.token != address(0), "InvestmentManager/tranche-does-not-exist"); // tranche must have been added
        require(_poolCurrencyCheck(_poolId, _currency), "InvestmentManager/currency-not-supported"); // currency must be supported by pool
        uint128 currencyId = currencyAddressToId[_currency];

        liquidityPool = liquidityPoolFactory.newLiquidityPool(
            _poolId,
            _trancheId,
            currencyId,
            _currency,
            tranche.token,
            address(this),
            address(gateway)
        );

        liquidityPools[_poolId][_trancheId][_currency] = liquidityPool;
        wards[liquidityPool] = 1;
        // enable connectors to take the liquidity pool tokens out of escrow in case if investments
        AuthLike(tranche.token).rely(liquidityPool); // add liquidityPool as ward on tranche Token

        emit LiquidityPoolDeployed(_poolId, _trancheId, liquidityPool);
        return liquidityPool;
    }

    function deployTranche(uint64 _poolId, bytes16 _trancheId) public returns (address) { 
        Tranche storage tranche = tranches[_poolId][_trancheId];
        require(tranche.token == address(0), "InvestmentManager/tranche-already-deployed"); 
        require(tranche.createdAt > 0, "InvestmentManager/tranche-not-added"); 
        // deploy liquidity pool set gateway as admin on liquidityPool & memberlist
        address memberlist = memberlistFactory.newMemberlist(address(gateway), address(this));
        MemberlistLike(memberlist).updateMember(address(escrow), type(uint256).max); // add escrow to tranche tokens memberlist
        
        address token = trancheTokenFactory.newTrancheToken(
            _poolId,
            _trancheId,
            address(this),
            memberlist,
            tranche.tokenName,
            tranche.tokenSymbol,
            tranche.decimals,
            address(gateway)
        );

        EscrowLike(escrow).approve(token, address(this), MAX_UINT256);
        tranche.token = token;
        emit TrancheTokenDeployed(_poolId, _trancheId);
        return token;
    }

    // ------ helper functions
    // TODO: check rounding
    function calcDepositPrice(address _user, address _liquidityPool)
        public
        view
        returns (uint128 userTrancheTokenPrice)
    {
        LPValues storage lpValues = orderbook[_user][_liquidityPool];
        if (lpValues.maxMint == 0) {
            return 0;
        }
        userTrancheTokenPrice = lpValues.maxDeposit / lpValues.maxMint;
    }

    function calcRedeemTokenPrice(address _user, address _liquidityPool)
        public
        view
        returns (uint128 userTrancheTokenPrice)
    {
        LPValues storage lpValues = orderbook[_user][_liquidityPool];
        if (lpValues.maxRedeem == 0) {
            return 0;
        }
        userTrancheTokenPrice = lpValues.maxWithdraw / lpValues.maxRedeem;
    }

    function _poolCurrencyCheck(uint64 _poolId, address _currencyAddress) internal view returns (bool) {
        uint128 currency = currencyAddressToId[_currencyAddress];
        require(currency != 0, "InvestmentManager/unknown-currency"); // currency index on the centrifuge chain side should start at 1
        require(allowedPoolCurrencies[_poolId][_currencyAddress], "InvestmentManager/pool-currency-not-allowed");
        return true;
    }

    function _liquidityPoolTokensCheck(uint64 _poolId, bytes16 _trancheId, address _currency, address _user)
        internal
        returns (bool)
    {
        LiquidityPoolLike lPool = LiquidityPoolLike(liquidityPools[_poolId][_trancheId][_currency]);
        require(address(lPool) != address(0), "InvestmentManager/unknown-liquidity-pool");
        require(lPool.hasMember(_user), "InvestmentManager/not-a-member");
        return true;
    }

    function _decreaseDepositLimits(address _user, address _liquidityPool, uint128 _currency, uint128 _trancheTokens)
        internal
    {
        LPValues storage values = orderbook[_user][_liquidityPool];
        if (values.maxDeposit < _currency) {
            values.maxDeposit = 0;
        } else {
            values.maxDeposit = values.maxDeposit - _currency;
        }
        if (values.maxMint < _trancheTokens) {
            values.maxMint = 0;
        } else {
            values.maxMint = values.maxMint - _trancheTokens;
        }
    }

    function _decreaseRedemptionLimits(address _user, address _liquidityPool, uint128 _currency, uint128 _trancheTokens)
        internal
    {
        LPValues storage values = orderbook[_user][_liquidityPool];
        if (values.maxWithdraw < _currency) {
            values.maxWithdraw = 0;
        } else {
            values.maxWithdraw = values.maxWithdraw - _currency;
        }
        if (values.maxRedeem < _trancheTokens) {
            values.maxRedeem = 0;
        } else {
            values.maxRedeem = values.maxRedeem - _trancheTokens;
        }
    }

    /// @dev safe type conversion from uint256 to uint128. Revert if value is too big to be stored with uint128. Avoid data loss.
    /// @return value - safely converted without data loss
    function _toUint128(uint256 _value) internal pure returns (uint128 value) {
        if (_value > MAX_UINT128) {
            revert();
        } else {
            value = uint128(_value);
        }
    }
}
