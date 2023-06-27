// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.18;
pragma abicoder v2;

import { LiquidityPoolFactoryLike, MemberlistFactoryLike } from "./liquidityPool/Factory.sol";
import { LiquidityPool } from "./liquidityPool/LiquidityPool.sol";
import { ERC20Like } from "./token/restricted.sol";
import { MemberlistLike } from "./token/memberlist.sol";
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
    function collectInvest(uint64 poolId, bytes16 trancheId, address investor) external;
    function collectRedeem(uint64 poolId, bytes16 trancheId, address investor) external;
    function paused() external returns(bool);
}

interface LiquidityPoolLike {
    // restricted token functions
    function memberlist() external returns (address);
    function hasMember(address) external returns (bool); 
    function file(bytes32 what, address data) external;
    // erc20 functions
    function mint(address, uint) external;
    function burn(address, uint) external;
    function balanceOf(address) external returns (uint);
    function transferFrom(address, address, uint) external returns (bool);
    // 4626 functions
    function updateTokenPrice(uint128 _tokenPrice) external;
    function asset() external returns (address);
    // centrifuge chain info functions
    function poolId() external returns (uint64);
    function trancheId() external returns (bytes16);
}

interface EscrowLike {
    function approve(address token, address spender, uint256 value) external;
}

/// @dev storing information about pools on Centrifuge chain
struct Pool {
    uint64 poolId;
    uint256 createdAt;
    bool isActive;
}

/// @dev storing information about tranches on Centrifuge chain
struct Tranche {
    uint64 poolId;
    bytes16 trancheId;
    uint256 createdAt;
    string tokenName;
    string tokenSymbol;
    uint8 decimals;
    address[] liquidityPools; 
 }

/// @dev storing liquidity pool orders and deposit/redemption limits for a user 
struct LPValues {
    uint128 maxDeposit;
    uint128 maxMint;
    uint128 maxWithdraw;
    uint128 maxRedeem;
    uint128 openRedeem;
    uint128 openInvest;
}

contract CentrifugeConnector is Auth {

    mapping(uint64 => Pool) public pools; // pools on Centrifuge chain

    mapping(uint64 => mapping(bytes16 => mapping(address => address))) public liquidityPools; // Centrifuge chain tranche -> currency -> liquidity pool address // Todo: add currency
    mapping(address => uint) public liquidityPoolWards; // liquidityPools that are allowed to call invest/redeem functions 
    mapping(uint64 => mapping(bytes16 => Tranche)) public tranches; // Centrifuge chain tranches
   
   // mapping(address => Tranche) public tranches; // liquidityPool -> Centrifuge chain tranches 
    mapping(address => mapping(address => LPValues)) public orderbook; // outstanding liquidity pool orders & limits per user & liquidity pool

    mapping(uint128 => address) public currencyIdToAddress;
    mapping(address => uint128) public currencyAddressToId; // The reverse mapping of `currencyIdToAddress`
    mapping(uint64 => mapping(address => bool)) public allowedPoolCurrencies;

    GatewayLike public gateway;
    EscrowLike public immutable escrow;

    LiquidityPoolFactoryLike public immutable liquidityPoolFactory; 
    MemberlistFactoryLike public immutable memberlistFactory;

    // --- Events ---
    event File(bytes32 indexed what, address data);
    event CurrencyAdded(uint128 indexed currency, address indexed currencyAddress);
    event PoolAdded(uint64 indexed poolId);
    event PoolCurrencyAllowed(uint128 indexed  currency, uint64 indexed poolId);
    event TrancheAdded(uint64 indexed poolId, bytes16 indexed trancheId);
    event TrancheDeployed(uint64 indexed poolId, bytes16 indexed trancheId, address indexed token);
    event DepositProcessed(address indexed liquidityPool, address indexed user, uint128 indexed currencyAmount);
    event RedemptionProcessed(address indexed liquidityPool, address indexed user, uint128 indexed trancheTokenAmount);
    event LiquidityPoolDeployed(uint64 indexed poolId, bytes16 indexed trancheId, address indexed liquidityPoool);

    constructor(address escrow_, address liquidityPoolFactory_, address memberlistFactory_) {
        escrow = EscrowLike(escrow_);
        liquidityPoolFactory = LiquidityPoolFactoryLike(liquidityPoolFactory_);
        memberlistFactory = MemberlistFactoryLike(memberlistFactory_);

        wards[msg.sender] = 1;
        emit Rely(msg.sender);
    }

    // --- Getters --- 
    function getLiquidityPoolsForTranche(uint64 _poolId, bytes16 _trancheId) public view returns (address[] memory liquidityPools) {
      liquidityPools = tranches[_poolId][_trancheId].liquidityPools; 
}

    /// @dev checks whether a Centrifuge pool is active - can be used to prevent deposit / redemption requests to/from certain pools & avoid transfers from escrow related to inactive pools.
    modifier poolActive() {
        LiquidityPoolLike lPool = LiquidityPoolLike(msg.sender);
        require(pools[lPool.poolId()].isActive, "CentrifugeConnector/pool-deactivated");
        _;
    }

    /// @dev checks whether gateway is active - can be used to prevent any interactions with centrifuge chain and stop all deposits & redemtions from escrow.
    modifier connectorActive() {
        require(gateway.paused(), "CentrifugeConnector/connector-deactivated");
        _;
    }

    modifier onlyGateway() {
        require(msg.sender == address(gateway), "CentrifugeConnector/not-the-gateway");
        _;
    }

   modifier onlyLiquidityPoolWard() {
        require(liquidityPoolWards[msg.sender] == 1, "CentrifugeConnector/not-liquidity-pool-ward");
        _;
    }

    // --- Administration ---
    function file(bytes32 what, address data) external auth {
        if (what == "gateway") gateway = GatewayLike(data);
        else revert("CentrifugeConnector/file-unrecognized-param");
        emit File(what, data);
    }

    /// @dev activate / deactivate pool
    function setPoolActive(uint64 _poolId, bool _isActive) external auth { 
        Pool storage pool = pools[_poolId];
        require(pool.createdAt > 0, "CentrifugeConnector/invalid-pool");
        pool.isActive = _isActive;
    }

    // --- liquidity pool outgoing message handling ---

    function requestRedeem(uint256 _trancheTokensAmount, address _user) onlyLiquidityPoolWard poolActive connectorActive public auth {
        address _liquidityPool = msg.sender;
        LPValues storage lpValues = orderbook[_user][ _liquidityPool];
        LiquidityPoolLike lPool = LiquidityPoolLike(_liquidityPool);
        uint128 trancheTokensAmount = _toUint128(_trancheTokensAmount);
    
        require(_poolCurrencyCheck(lPool.poolId(), lPool.asset()), "CentrifugeConnector/currency-not-supported");
        require(_trancheTokenCheck(lPool.poolId(), lPool.trancheId(), lPool.asset(), _user), "CentrifugeConnector/tranche-tokens-not-supported");
       
        if (lpValues.openInvest > 0) { // cancel outstanding deposit orders 
           gateway.decreaseInvestOrder(lPool.poolId(), lPool.trancheId(), _user, currencyAddressToId[lPool.asset()], uint128(lpValues.openInvest));
        }
        if(trancheTokensAmount == 0) { // case: user only wants to cancel outstanding orders
            return;
        }

        if(lpValues.maxMint >= trancheTokensAmount) { // case: user has unclaimed trancheTokens in escrow -> more than redemption request
            uint128 userTrancheTokenPrice = calcCustomTrancheTokenPrice( _user, _liquidityPool);
            uint128 assets = trancheTokensAmount * userTrancheTokenPrice;
            _decreaseDepositLimits(_user, _liquidityPool, assets, trancheTokensAmount);
        } else {
            uint transferAmount = trancheTokensAmount - lpValues.maxMint;
            lpValues.maxDeposit = 0;
            lpValues.maxMint = 0;

            require(lPool.balanceOf(_user) >= trancheTokensAmount, "CentrifugeConnector/insufficient-tranche-token-balance");
            require(lPool.transferFrom(_user, address(escrow), transferAmount), "CentrifugeConnector/tranche-token-transfer-failed");
        } 

        gateway.increaseRedeemOrder(lPool.poolId(), lPool.trancheId(), _user, currencyAddressToId[lPool.asset()], trancheTokensAmount);
    }
    
    function requestDeposit(uint _currencyAmount, address _user) onlyLiquidityPoolWard poolActive connectorActive public auth {
        address _liquidityPool = msg.sender;
        LPValues storage lpValues = orderbook[_user][ _liquidityPool];
        LiquidityPoolLike lPool = LiquidityPoolLike(_liquidityPool);
        ERC20Like currency = ERC20Like(lPool.asset());
        uint128 currencyAmount = _toUint128(_currencyAmount);

        require(_poolCurrencyCheck(lPool.poolId(), lPool.asset()), "CentrifugeConnector/currency-not-supported");
        require(_trancheTokenCheck(lPool.poolId(), lPool.trancheId(), lPool.asset(), _user), "CentrifugeConnector/tranche-tokens-not-supported");

        if (lpValues.openRedeem > 0) { // cancel outstanding redeem orders 
            gateway.decreaseRedeemOrder(lPool.poolId(), lPool.trancheId(), _user, currencyAddressToId[lPool.asset()], uint128(lpValues.openRedeem));
        }
        if(currencyAmount == 0) { // case: user only wants to cancel outstanding redemptions
            return; 
        }
        if(lpValues.maxWithdraw >= currencyAmount) { // case: user has some claimable fund in escrow -> funds > Deposit request
            uint128 userTrancheTokenPrice = calcCustomTrancheTokenPrice( _user, _liquidityPool);
            uint128 trancheTokens = currencyAmount / userTrancheTokenPrice;
            _decreaseRedemptionLimits(_user, _liquidityPool, currencyAmount, trancheTokens);
        } else {
            uint128 transferAmount = currencyAmount - lpValues.maxWithdraw;
            lpValues.maxWithdraw = 0;
            lpValues.maxRedeem = 0;

            require(currency.balanceOf(_user) >= transferAmount, "CentrifugeConnector/insufficient-balance");
            require(currency.transferFrom(_user, address(escrow), transferAmount), "CentrifugeConnector/currency-transfer-failed");
        } 

        gateway.increaseInvestOrder(lPool.poolId(), lPool.trancheId(), _user, currencyAddressToId[lPool.asset()], currencyAmount);
    }

   // --- public outgoing message handling ---

    function collectInvest(uint64 _poolId, bytes16 _trancheId, address _currency) public {
        LiquidityPoolLike lPool = LiquidityPoolLike(liquidityPools[_poolId][_trancheId][_currency]);
        require(address(lPool) != address(0), "CentrifugeConnector/unknown-liquidity-pool");
        require(lPool.hasMember(msg.sender), "CentrifugeConnector/not-a-member");

        gateway.collectInvest(_poolId, _trancheId, address(msg.sender));
    }

    function collectRedeem(uint64 _poolId, bytes16 _trancheId, address _currency) public {
        LiquidityPoolLike lPool = LiquidityPoolLike(liquidityPools[_poolId][_trancheId][_currency]);
        require(address(lPool) != address(0), "CentrifugeConnector/unknown-liquidity-pool");
        require(lPool.hasMember(msg.sender), "CentrifugeConnector/not-a-member");

        gateway.collectRedeem(_poolId, _trancheId, address(msg.sender));
    }
         
    function transfer(address currencyAddress, bytes32 recipient, uint128 amount) public {
        uint128 currency = currencyAddressToId[currencyAddress];
        require(currency != 0, "CentrifugeConnector/unknown-currency");

        ERC20Like erc20 = ERC20Like(currencyAddress);
        require(erc20.balanceOf(msg.sender) >= amount, "CentrifugeConnector/insufficient-balance");
        require(erc20.transferFrom(msg.sender, address(escrow), amount), "CentrifugeConnector/currency-transfer-failed");

        gateway.transfer(currency, msg.sender, recipient, amount);
    }

    function transferTrancheTokensToCentrifuge(
        uint64 poolId,
        bytes16 trancheId,
        address currency, // we need this as there is liquidityPool per supported currency
        bytes32 destinationAddress,
        uint128 amount
    ) public {
        LiquidityPoolLike lPool = LiquidityPoolLike(liquidityPools[poolId][trancheId][currency]);
        require(address(lPool) != address(0), "CentrifugeConnector/unknown-token");

        require(lPool.balanceOf(msg.sender) >= amount, "CentrifugeConnector/insufficient-balance");
        lPool.burn(msg.sender, amount);

        gateway.transferTrancheTokensToCentrifuge(poolId, trancheId, msg.sender, destinationAddress, amount);
    }

    function transferTrancheTokensToEVM(
        uint64 poolId,
        bytes16 trancheId,
        address currency,
        uint64 destinationChainId,
        address destinationAddress,
        uint128 amount
    ) public {
        LiquidityPoolLike lPool = LiquidityPoolLike(liquidityPools[poolId][trancheId][currency]);
        require(address(lPool) != address(0), "CentrifugeConnector/unknown-token");

        require(lPool.balanceOf(msg.sender) >= amount, "CentrifugeConnector/insufficient-balance");
        lPool.burn(msg.sender, amount);

        gateway.transferTrancheTokensToEVM(
            poolId, trancheId, msg.sender, destinationChainId, destinationAddress, amount
        );
    }

    // --- Incoming message handling ---
    /// @dev a global chain agnostic currency index is maintained on centrifuge chain. This function maps a currency from the centrifuge chain index to its corresponding address on the evm chain.
    /// The chain agnostic currency id has to be used to pass currency information to the centrifuge chain.
    /// @notice this function can only be executed by the gateway contract.
    function addCurrency(uint128 currency, address currencyAddress) public onlyGateway {
        // currency index on the centrifuge chain side should start at 1
        require(currency > 0, "CentrifugeConnector/currency-id-has-to-be-greater-than-0");
        require(currencyIdToAddress[currency] == address(0), "CentrifugeConnector/currency-id-in-use");
        require(currencyAddressToId[currencyAddress] == 0, "CentrifugeConnector/currency-address-in-use");

        currencyIdToAddress[currency] = currencyAddress;
        currencyAddressToId[currencyAddress] = currency;
        emit CurrencyAdded(currency, currencyAddress);
    }

    /// @dev new pool details from an existing centrifuge chain pool are added.
    /// @notice the function can only be executed by the gateway contract.
    function addPool(uint64 poolId) public onlyGateway {
        Pool storage pool = pools[poolId];
        require(pool.createdAt == 0, "CentrifugeConnector/pool-already-added");
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
        require(pool.createdAt > 0, "CentrifugeConnector/invalid-pool");

        address currencyAddress = currencyIdToAddress[currency];
        require(currencyAddress != address(0), "CentrifugeConnector/unknown-currency");

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
        require(pool.createdAt > 0, "CentrifugeConnector/invalid-pool");
        Tranche storage tranche = tranches[_poolId][_trancheId];
        require(tranche.createdAt == 0, "CentrifugeConnector/tranche-already-exists");
        
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
        require(tranche.createdAt > 0, "CentrifugeConnector/invalid-pool-or-tranche");
        for (uint i=0; i<tranche.liquidityPools.length; i++) {
            address lPool = tranche.liquidityPools[i];
            require(lPool != address(0), "CentrifugeConnector/invalid-liquidity-pool");
            LiquidityPoolLike(lPool).updateTokenPrice(_price);
        }
    }

    function updateMember(uint64 _poolId, bytes16 _trancheId, address _user, uint64 _validUntil) public onlyGateway {
        Tranche storage tranche = tranches[_poolId][_trancheId];
        require(tranche.createdAt > 0, "CentrifugeConnector/invalid-pool-or-tranche");
        for (uint i=0; i<tranche.liquidityPools.length; i++) {
            address lPool_ = tranche.liquidityPools[i];
            require(lPool_ != address(0), "CentrifugeConnector/invalid-liquidity-pool");
            LiquidityPoolLike lPool = LiquidityPoolLike(lPool_);
            MemberlistLike memberlist = MemberlistLike(lPool.memberlist());
            memberlist.updateMember(_user, _validUntil);
        }
    }

    function handleCollectInvest(uint64 _poolId, bytes16 _trancheId, address _recepient, uint128 _currency, uint128 _currencyInvested, uint128 _tokensPayout, uint128 _remainingInvestOrder) public onlyGateway {
        require(_currencyInvested != 0, "CentrifugeConnector/zero-invest");
        address currency = currencyIdToAddress[_currency];
        address lPool = liquidityPools[_poolId][_trancheId][currency];
        require(lPool != address(0), "CentrifugeConnector/tranche-does-not-exist");
        
        LPValues storage values = orderbook[_recepient][lPool];
        values.openInvest = _remainingInvestOrder;
        values.maxDeposit = values.maxDeposit + _currencyInvested;
        values.maxMint = values.maxMint + _tokensPayout;

        LiquidityPoolLike(lPool).mint(address(escrow), _tokensPayout); // mint to escrow. Recepeint can claim by calling withdraw / redeem
    }

    function handleCollectRedeem(uint64 _poolId, bytes16 _trancheId, address _recepient, uint128 _currency, uint128 _currencyPayout, uint128 _trancheTokensRedeemed, uint128 _remainingRedeemOrder) public onlyGateway {
        require(_trancheTokensRedeemed != 0, "CentrifugeConnector/zero-redeem");
        address currency = currencyIdToAddress[_currency];
        address lPool = liquidityPools[_poolId][_trancheId][currency];
        require(lPool != address(0), "CentrifugeConnector/tranche-does-not-exist");
        
        LPValues storage values = orderbook[_recepient][lPool];
        values.openRedeem = _remainingRedeemOrder;
        values.maxWithdraw = values.maxWithdraw + _currencyPayout;
        values.maxRedeem = values.maxRedeem + _trancheTokensRedeemed;

        LiquidityPoolLike(lPool).burn(address(escrow), _trancheTokensRedeemed); // burned redeemed tokens from escrow
    } 

    function handleDecreaseInvestOrder(uint64 _poolId, bytes16 _trancheId, address _user, uint128 _currency, uint128 _currencyPayout, uint128 _remainingInvestOrder) public onlyGateway {
        require(_currencyPayout != 0, "CentrifugeConnector/zero-payout");
        address currency = currencyIdToAddress[_currency]; 
        LiquidityPoolLike lPool  = LiquidityPoolLike(liquidityPools[_poolId][_trancheId][currency]);
        require(address(lPool) != address(0), "CentrifugeConnector/tranche-does-not-exist");
        require(allowedPoolCurrencies[_poolId][currency], "CentrifugeConnector/pool-currency-not-allowed");
        require(currency != address(0), "CentrifugeConnector/unknown-currency");
        require(currency == lPool.asset(), "CentrifugeConnector/not-tranche-currency");

        // TODO: escrow should give max approval on deployment
        EscrowLike(escrow).approve(currency, address(this), _currencyPayout);
   
        require(
            ERC20Like(currency).transferFrom(address(escrow), _user, _currencyPayout),
            "CentrifugeConnector/currency-transfer-failed"
        );
        orderbook[_user][address(lPool)].openInvest = _remainingInvestOrder;
    }

    function handleDecreaseRedeemOrder(uint64 _poolId, bytes16 _trancheId, address _user, uint128 _currency, uint128 _tokensPayout, uint128 _remainingRedeemOrder) public onlyGateway {
        require(_tokensPayout != 0, "CentrifugeConnector/zero-payout");
        address currency = currencyIdToAddress[_currency];
        LiquidityPoolLike lPool = LiquidityPoolLike(liquidityPools[_poolId][_trancheId][currency]);
        require(address(lPool) != address(0), "CentrifugeConnector/tranche-does-not-exist");
       
        require(LiquidityPoolLike(lPool).hasMember(_user), "CentrifugeConnector/not-a-member");
        // TODO: escrow should give max approval on deployment
        EscrowLike(escrow).approve(address(lPool), address(this), _tokensPayout);
        require(
            lPool.transferFrom(address(escrow), _user, _tokensPayout),
            "CentrifugeConnector/trancheTokens-transfer-failed"
        );
        orderbook[_user][address(lPool)].openRedeem = _remainingRedeemOrder;
    }

    function handleTransfer(uint128 currency, address recipient, uint128 amount) public onlyGateway {
        address currencyAddress = currencyIdToAddress[currency];
        require(currencyAddress != address(0), "CentrifugeConnector/unknown-currency");

        EscrowLike(escrow).approve(currencyAddress, address(this), amount);
        require(
            ERC20Like(currencyAddress).transferFrom(address(escrow), recipient, amount),
            "CentrifugeConnector/currency-transfer-failed"
        );
    }

     /// @dev In the current implementation: a tranche token on Centrifuge chain side is mapped to multiple liquidity pool tokens. One for each currency supported. 
     /// @notice currencyId is required in order to identify the liquidity pool for the token mint. 

    function handleTransferTrancheTokens(uint64 _poolId, bytes16 _trancheId, uint128 _currencyId, address _destinationAddress, uint128 _amount)
        public
        onlyGateway
    {
        address currency = currencyIdToAddress[_currencyId];
        address liquidityPool_ = liquidityPools[_poolId][_trancheId][currency];
        require(liquidityPool_ != address(0), "CentrifugeConnector/unknown-liquidityPool");
        LiquidityPoolLike liquidityPool = LiquidityPoolLike(liquidityPool_);
        require(liquidityPool.hasMember(_destinationAddress), "CentrifugeConnector/not-a-member");
        liquidityPool.mint(_destinationAddress, _amount);
    }

    // ----- liquidity pool functions 

    // --- Liquidity Pool Function ---
    /// @dev calculates the avg share price for the deposited assets of a specific user
    /// @return currencyAmount is type of uin256 to support the EIP4626 Liquidity Pool interface
    function maxDeposit(address _user, address _liquidityPool) public view returns (uint256 currencyAmount) {
        currencyAmount = uint256(orderbook[_user][_liquidityPool].maxDeposit);
    }

    /// @dev 
    /// @return trancheTokenAmount type of uin256 to support the EIP4626 Liquidity Pool interface 
    function maxMint(address _user, address _liquidityPool) public view returns (uint256 trancheTokenAmount) {
        trancheTokenAmount = uint256(orderbook[_user][_liquidityPool].maxMint);
    }

    /// @dev 
    /// @return currencyAmount type of uin256 to support the EIP4626 Liquidity Pool interface 
    function maxWithdraw(address _user, address _liquidityPool) public view returns (uint256 currencyAmount) {
        currencyAmount = uint256(orderbook[_user][_liquidityPool].maxWithdraw);
    }

    /// @dev 
    /// @return trancheTokenAmount type of uin256 to support the EIP4626 Liquidity Pool interface 
    function maxRedeem(address _user, address _liquidityPool) public view returns (uint256 trancheTokenAmount) {
        trancheTokenAmount = uint256(orderbook[_user][_liquidityPool].maxRedeem);
    }  

    /// @dev processes user's currency deposit / investment after the epoch has been executed on Centrifuge chain.
    /// In case user's invest order was fullfilled on Centrifuge chain during epoch execution MaxDeposit and MaxMint are increased and trancheTokens can be transferred to user's wallet on calling processDeposit.
    /// Note: The currency required to fullfill the invest order is already locked in escrow upon calling requestDeposit.
    /// @notice trancheTokenAmount return value is type of uint256 to be compliant with EIP4626 LiquidityPool interface
    /// @return trancheTokenAmount the amount of trancheTokens transferred to the user's wallet after successful depoit
    function processDeposit(address _user, uint256 _currencyAmount) public onlyLiquidityPoolWard connectorActive poolActive auth returns (uint256) {
        address _liquidityPool = msg.sender;
        uint128 currencyAmount = _toUint128(_currencyAmount);
        LiquidityPoolLike lPool = LiquidityPoolLike(_liquidityPool);

        require((currencyAmount <= orderbook[_user][_liquidityPool].maxDeposit), "CentrifugeConnector/amount-exceeds-deposit-limits");
        uint128 userTrancheTokenPriceLP = calcCustomTrancheTokenPrice( _user, _liquidityPool);
        require((userTrancheTokenPriceLP > 0), "LiquidityPool/amount-exceeds-deposit-limits");
        uint128 trancheTokenAmount = currencyAmount / userTrancheTokenPriceLP;

        _decreaseDepositLimits(_user, _liquidityPool, currencyAmount, trancheTokenAmount); // decrease user's deposit limits for this lp
        require(lPool.hasMember( _user), "CentrifugeConnector/trancheTokens-not-a-member");
        require(lPool.transferFrom(address(escrow), _user, trancheTokenAmount), "CentrifugeConnector/trancheTokens-transfer-failed");
        
        emit DepositProcessed(_liquidityPool, _user, currencyAmount);
        return uint256(trancheTokenAmount);
    }

    /// @dev processes user's currency deposit / investment after the epoch has been executed on Centrifuge chain.
    /// In case user's invest order was fullfilled on Centrifuge chain during epoch execution MaxDeposit and MaxMint are increased and trancheTokens can be transferred to user's wallet on calling processDeposit or processMint.
    /// Note: The currency amount required to fullfill the invest order is already locked in escrow upon calling requestDeposit.
    /// Note: The tranche tokens are already minted on collectInvest and are deposited to the escrow account until the users calls mint, or deposit.
    /// @notice currencyAmount return value is type of uint256 to be compliant with EIP4626 LiquidityPool interface
    /// @return currencyAmount the amount of liquidityPool assets invested and locked in escrow in order for the amount of tranche received after successful investment into the pool.
    function processMint(address _user, uint256 _trancheTokenAmount) public onlyLiquidityPoolWard poolActive connectorActive auth returns (uint256) {
        address _liquidityPool = msg.sender;
        uint128 trancheTokenAmount = _toUint128(_trancheTokenAmount);
        LiquidityPoolLike lPool = LiquidityPoolLike(_liquidityPool);

        require((trancheTokenAmount <= orderbook[_user][ _liquidityPool].maxMint), "CentrifugeConnector/amount-exceeds-mint-limits");
        uint128 userTrancheTokenPriceLP = calcCustomTrancheTokenPrice(_user,  _liquidityPool);
        require((userTrancheTokenPriceLP > 0), "LiquidityPool/amount-exceeds-mint-limits");
        uint128 currencyAmount = trancheTokenAmount * userTrancheTokenPriceLP;

        _decreaseDepositLimits(_user,  _liquidityPool, currencyAmount, trancheTokenAmount); // decrease the possible deposit limits
        require(lPool.hasMember( _user), "CentrifugeConnector/trancheTokens-not-a-member");
        require(lPool.transferFrom(address(escrow), _user, trancheTokenAmount), "CentrifugeConnector/trancheTokens-transfer-failed");

        emit DepositProcessed(_liquidityPool, _user, currencyAmount);
        return uint256(currencyAmount); 
    }

    /// @dev processes user's trancheToken redemption after the epoch has been executed on Centrifuge chain.
    /// In case user's redempion order was fullfilled on Centrifuge chain during epoch execution MaxRedeem and MaxWithdraw are increased and LiquidityPool currency can be transferred to user's wallet on calling processRedeem or processWithdraw.
    /// Note: The trancheToken amount required to fullfill the redemption order was already locked in escrow upon calling requestRedeem and burned upon collectRedeem.
    /// @notice currencyAmount return value is type of uint256 to be compliant with EIP4626 LiquidityPool interface
    /// @return currencyAmount the amount of liquidityPool assets received for the amount of redeemed/burned trancheTokens.
    function processRedeem(uint256 _trancheTokenAmount, address _receiver, address _user) public onlyLiquidityPoolWard poolActive connectorActive auth returns (uint256) {
        address _liquidityPool = msg.sender;
        uint128 trancheTokenAmount = _toUint128(_trancheTokenAmount);
        LiquidityPoolLike lPool = LiquidityPoolLike(_liquidityPool);

        require((trancheTokenAmount <= orderbook[_user][ _liquidityPool].maxRedeem), "CentrifugeConnector/amount-exceeds-redeem-limits");
        uint128 userTrancheTokenPriceLP = calcCustomTrancheTokenPrice(_user, _liquidityPool);
        require((userTrancheTokenPriceLP > 0), "LiquidityPool/amount-exceeds-redemption-limits");
        uint128 currencyAmount = trancheTokenAmount * userTrancheTokenPriceLP;
       
        _decreaseRedemptionLimits(_user,  _liquidityPool, currencyAmount, trancheTokenAmount); // decrease the possible deposit limits
        require(ERC20Like(lPool.asset()).transferFrom(address(escrow), _receiver, currencyAmount), "CentrifugeConnector/shares-transfer-failed");
        
        emit RedemptionProcessed(_liquidityPool, _user, trancheTokenAmount);
        return uint256(currencyAmount); 
    }

    /// @dev processes user's trancheToken redemption after the epoch has been executed on Centrifuge chain.
    /// In case user's redempion order was fullfilled on Centrifuge chain during epoch execution MaxRedeem and MaxWithdraw are increased and LiquidityPool currency can be transferred to user's wallet on calling processRedeem or processWithdraw.
    /// Note: The trancheToken amount required to fullfill the redemption order was already locked in escrow upon calling requestRedeem and burned upon collectRedeem.
    /// @notice trancheTokenAmount return value is type of uint256 to be compliant with EIP4626 LiquidityPool interface
    /// @return trancheTokenAmount the amount of trancheTokens redeemed/burned required to receive the currencyAmount payout/withdrawel.
    function processWithdraw(uint256 _currencyAmount, address _receiver, address _user) public onlyLiquidityPoolWard poolActive connectorActive auth returns (uint256) {
        address _liquidityPool = msg.sender;
        uint128 currencyAmount = _toUint128(_currencyAmount);
        LiquidityPoolLike lPool = LiquidityPoolLike(_liquidityPool);

        require((currencyAmount <= orderbook[_user][ _liquidityPool].maxWithdraw), "CentrifugeConnector/amount-exceeds-withdraw-limits");
        uint128 userTrancheTokenPriceLP = calcCustomTrancheTokenPrice(_user, _liquidityPool);
        require((userTrancheTokenPriceLP > 0), "LiquidityPool/amount-exceeds-withdraw-limits");
        uint128 trancheTokenAmount = currencyAmount / userTrancheTokenPriceLP;

        _decreaseRedemptionLimits(_user,  _liquidityPool, currencyAmount, trancheTokenAmount);
        require(ERC20Like(lPool.asset()).transferFrom(address(escrow), _receiver, currencyAmount), "CentrifugeConnector/trancheTokens-transfer-failed");
        return uint256(trancheTokenAmount);
    }


    // ----- public functions
    function deployLiquidityPool(   
        uint64 _poolId,
        bytes16 _trancheId,
        address _currency
        ) public returns (address) {

        address liquidityPool = liquidityPools[_poolId][_trancheId][_currency];
        require(liquidityPool == address(0), "CentrifugeConnector/liquidityPool-already-deployed");
        require(pools[_poolId].createdAt > 0, "CentrifugeConnector/pool-does-not-exist");
        Tranche storage tranche = tranches[_poolId][_trancheId];
        require(tranche.createdAt != 0, "CentrifugeConnector/tranche-does-not-exist"); // tranche must have been added
        require(_poolCurrencyCheck(_poolId, _currency), "CentrifugeConnector/currency-not-supported"); // currency must be supported by pool
        uint128 currencyId = currencyAddressToId[_currency];

        // gateway admin on liquidityPool & memberlist
        address memberlist = memberlistFactory.newMemberlist(address(gateway), address(this));
        MemberlistLike(memberlist).updateMember(address(escrow), type(uint256).max); // add escrow to tranche tokens memberlist
        liquidityPool = liquidityPoolFactory.newLiquidityPool(_poolId, _trancheId, currencyId, _currency, address(this), address(gateway), memberlist, tranche.tokenName, tranche.tokenSymbol, tranche.decimals);
        liquidityPools[_poolId][_trancheId][_currency] = liquidityPool;
        liquidityPoolWards[liquidityPool] = 1; // give liquidityPool permissions, so that invest & redeem functions can be called
        tranche.liquidityPools.push(liquidityPool);
       
        emit LiquidityPoolDeployed(_poolId, _trancheId, liquidityPool);
        return liquidityPool;
    }
                                
     // ------ helper functions 
    function calcCustomTrancheTokenPrice(address _user, address _liquidityPool) public view returns (uint128 userTrancheTokenPrice) {
        LPValues storage lpValues = orderbook[_user][_liquidityPool];
        if(lpValues.maxMint == 0) {
            return 0;
        }
        userTrancheTokenPrice = lpValues.maxDeposit / lpValues.maxMint;
    }

    function _poolCurrencyCheck(uint64 _poolId, address _currencyAddress) internal view returns (bool) {
        uint128 currency = currencyAddressToId[_currencyAddress];
        require(currency != 0, "CentrifugeConnector/unknown-currency"); // currency index on the centrifuge chain side should start at 1
        require(allowedPoolCurrencies[_poolId][_currencyAddress], "CentrifugeConnector/pool-currency-not-allowed");
        return true;
    }
    
    function _trancheTokenCheck(uint64 _poolId, bytes16 _trancheId, address _currency, address _user) internal returns (bool) {
        LiquidityPoolLike lPool = LiquidityPoolLike(liquidityPools[_poolId][_trancheId][_currency]);
        require(address(lPool) != address(0), "CentrifugeConnector/unknown-liquidity-pool");
        require(lPool.hasMember(_user), "CentrifugeConnector/not-a-member");
        return true;
    }

    function _decreaseDepositLimits(address _user, address _liquidityPool, uint128 _currency, uint128 _trancheTokens) internal {
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

    function _decreaseRedemptionLimits(address _user, address _liquidityPool, uint128 _currency, uint128 _trancheTokens) internal {
        LPValues storage values = orderbook[_user][_liquidityPool];
        if (values.maxWithdraw < _currency) {
            values.maxDeposit = 0;
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
        if (_value > 2 ** 128) {
            revert();
        } else {
            value = uint128(_value);
        }
    }
}
