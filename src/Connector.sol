// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.18;
pragma abicoder v2;

import { LiquidityPoolFactoryLike, MemberlistFactoryLike } from "./liquidityPool/Factory.sol";
import { LiquidityPool } from "./liquidityPool/LiquidityPool.sol";
import {ERC20Like} from "./token/restricted.sol";
import {MemberlistLike} from "./token/memberlist.sol";
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
    function active() external returns(bool);
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
 }

// /// @dev storing information about liquidity pools on EVM chain. One tranche on Centrifuge chain can have multiple corresponding liquidity pools on an EVM chain.
struct LiquidityPoolInfo { 
    uint64 poolId;
    bytes16 trancheId;
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
    mapping(uint64 => mapping(bytes16 => Tranche)) public tranches; // Centrifuge chain tranches
    mapping(address => LiquidityPoolInfo) public addressToLiquidityPoolInfo;
   
   // mapping(address => Tranche) public tranches; // liquidityPool -> Centrifuge chain tranches 
    mapping(address => mapping(address => LPValues)) public orderbook; // outstanding liquidity pool orders & limits per user & liquidity pool

    mapping(uint128 => address) public currencyIdToAddress;
    mapping(address => uint128) public currencyAddressToId; // The reverse mapping of `currencyIdToAddress`
    mapping(uint64 => mapping(address => bool)) public allowedPoolCurrencies;

    GatewayLike public gateway;
    EscrowLike public immutable escrow;

    LiquidityPoolFactoryLike public immutable liquidityPoolFactory; //TODO use for LPPool deployment
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

    /// @dev checks whether a Centrifuge pool is active - can be used to prevent deposit / redemption requests to/from certain pools & avoid transfers from escrow related to inactive pools.
    modifier poolActive(address _liquidityPool) {
        LiquidityPoolInfo storage lp = addressToLiquidityPoolInfo[_liquidityPool];
        require(pools[lp.poolId].isActive, "CentrifugeConnector/pool-deactivated");
        _;
    }

    /// @dev checks whether gateway is active - can be used to prevent any interactions with centrifuge chain and stop all deposits & redemtions from escrow.
    modifier connectorActive() {
        require(gateway.active(), "CentrifugeConnector/connector-deactivated");
        _;
    }

    modifier onlyGateway() {
        require(msg.sender == address(gateway), "CentrifugeConnector/not-the-gateway");
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

    // --- Liquidity Pool Function ---
    /// @dev calculates the avg share price for the deposited assets of a specific user
    /// @dev
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
    function processDeposit(address _liquidityPool, address _user, uint256 _currencyAmount) public poolActive(_liquidityPool) connectorActive auth returns (uint256) {
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
    function processMint(address _liquidityPool, address _user, uint256 _trancheTokenAmount) public poolActive(_liquidityPool) connectorActive auth returns (uint256) {
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
    function processRedeem(address _liquidityPool, uint256 _trancheTokenAmount, address _receiver, address _user) public poolActive(_liquidityPool) connectorActive auth returns (uint256) {
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
    function processWithdraw(address _liquidityPool, uint256 _currencyAmount, address _receiver, address _user) public poolActive(_liquidityPool) connectorActive auth returns (uint256) {
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

    function requestRedeem(address _liquidityPool, uint256 _trancheTokensAmount, address _user) connectorActive poolActive(_liquidityPool) public auth {
        LPValues memory userValues = orderbook[_user][ _liquidityPool];
        Tranche memory cTranche = tranches[ _liquidityPool];
        LiquidityPoolLike tranche = LiquidityPoolLike( _liquidityPool);

        require(_poolCurrencyCheck(cTranche.poolId, tranche.asset()), "CentrifugeConnector/currency-not-supported");
        require(_trancheTokenCheck(cTranche.poolId, cTranche.trancheId, _user), "CentrifugeConnector/tranche-tokens-not-supported");
       
        if (userValues.openInvest > 0) { // cancel outstanding deposit orders 
            // replace
           gateway.decreaseInvestOrder(cTranche.poolId, cTranche.trancheId, _user, currencyAddressToId[tranche.asset()], uint128(userValues.openInvest));
        }
        if(_trancheTokensAmount == 0) { // case: user justwants to cancel outstanding orders
            return;
        }

        if(userValues.maxMint >= _trancheTokensAmount) { // case: user has unclaimed trancheTokens in escrow -> more than redemption request
            uint256 userTrancheTokenPrice = calcCustomTrancheTokenPrice( _user, _liquidityPool);
            uint256 assets = _trancheTokensAmount * userTrancheTokenPrice;
            _decreaseDepositLimits(_user, _liquidityPool, assets, _trancheTokensAmount);
        } else {
            uint transferAmount = _trancheTokensAmount - userValues.maxMint;
            userValues.maxDeposit = 0;
            userValues.maxMint = 0;

            require(tranche.balanceOf(_user) >= _trancheTokensAmount, "CentrifugeConnector/insufficient-tranche-token-balance");
            require(tranche.transferFrom(_user, address(escrow), transferAmount), "CentrifugeConnector/tranche-token-transfer-failed");
        } 

        gateway.increaseRedeemOrder(cTranche.poolId, cTranche.trancheId, _user, currencyAddressToId[tranche.asset()], uint128(_trancheTokensAmount));
    }
    
    function requestDeposit(address _liquidityPool, uint _currencyAmount, address _user) connectorActive poolActive(_liquidityPool) public auth {
        LPValues memory userValues = orderbook[_user][ _liquidityPool];
        Tranche memory cTranche = tranches[ _liquidityPool];
        LiquidityPoolLike tranche = LiquidityPoolLike( _liquidityPool);
        ERC20Like currency = ERC20Like(LiquidityPoolLike( _liquidityPool).asset());

        require(_poolCurrencyCheck(cTranche.poolId, tranche.asset()), "CentrifugeConnector/currency-not-supported");
        require(_trancheTokenCheck(cTranche.poolId, cTranche.trancheId, _user), "CentrifugeConnector/tranche-tokens-not-supported");

        if (userValues.openRedeem > 0) { // cancel outstanding redeem orders 
            gateway.decreaseRedeemOrder(cTranche.poolId, cTranche.trancheId, _user, currencyAddressToId[tranche.asset()], uint128(userValues.openRedeem));
        }
        if(_currencyAmount == 0) { // case: user only wants to cancel outstanding redemptions
            return; 
        }
        if(userValues.maxWithdraw >= _currencyAmount) { // case: user has some claimable fund in escrow -> funds > Deposit request
            uint256 userTrancheTokenPrice = calcCustomTrancheTokenPrice( _user, _liquidityPool);
            uint256 trancheTokens = _currencyAmount / userTrancheTokenPrice;
            _decreaseRedemptionLimits(_user, _liquidityPool, _currencyAmount, trancheTokens);
        } else {
            uint transferAmount = _currencyAmount - userValues.maxWithdraw;
            userValues.maxWithdraw = 0;
            userValues.maxRedeem = 0;

            require(currency.balanceOf(_user) >= transferAmount, "CentrifugeConnector/insufficient-balance");
            require(currency.transferFrom(_user, address(escrow), transferAmount), "CentrifugeConnector/currency-transfer-failed");
        } 

        gateway.increaseInvestOrder(cTranche.poolId, cTranche.trancheId, _user, currencyAddressToId[tranche.asset()], uint128(_currencyAmount));
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
        bytes32 destinationAddress,
        uint128 amount
    ) public {
        LiquidityPoolLike lPool = LiquidityPoolLike(liquidityPools[poolId][trancheId]);
        require(address(lPool) != address(0), "CentrifugeConnector/unknown-token");

        require(lPool.balanceOf(msg.sender) >= amount, "CentrifugeConnector/insufficient-balance");
        lPool.burn(msg.sender, amount);

        gateway.transferTrancheTokensToCentrifuge(poolId, trancheId, msg.sender, destinationAddress, amount);
    }

    function transferTrancheTokensToEVM(
        uint64 poolId,
        bytes16 trancheId,
        uint64 destinationChainId,
        address destinationAddress,
        uint128 amount
    ) public {
        LiquidityPoolLike tranche = LiquidityPoolLike(liquidityPools[poolId][trancheId]);
        require(address(tranche) != address(0), "CentrifugeConnector/unknown-token");

        require(tranche.balanceOf(msg.sender) >= amount, "CentrifugeConnector/insufficient-balance");
        tranche.burn(msg.sender, amount);

        gateway.transferTrancheTokensToEVM(
            poolId, trancheId, msg.sender, destinationChainId, destinationAddress, amount
        );
    }

    function collectInvest(uint64 _poolId, bytes16 _trancheId) public {
        LiquidityPoolLike tranche = LiquidityPoolLike(liquidityPools[_poolId][_trancheId]);
        require(address(tranche) != address(0), "CentrifugeConnector/unknown-tranche-token");
        require(tranche.hasMember(msg.sender), "CentrifugeConnector/not-a-member");

        gateway.collectInvest(_poolId, _trancheId, address(msg.sender));
    }

    function collectRedeem(uint64 _poolId, bytes16 _trancheId) public {
        LiquidityPoolLike tranche = LiquidityPoolLike(liquidityPools[_poolId][_trancheId]);
        require(address(tranche) != address(0), "CentrifugeConnector/unknown-tranche-token");
        require(tranche.hasMember(msg.sender), "CentrifugeConnector/not-a-member");

        gateway.collectRedeem(_poolId, _trancheId, address(msg.sender));
    }

    // --- Incoming message handling ---
    function addCurrency(uint128 currency, address currencyAddress) public onlyGateway {
        require(currencyIdToAddress[currency] == address(0), "CentrifugeConnector/currency-id-in-use");
        require(currencyAddressToId[currencyAddress] == 0, "CentrifugeConnector/currency-address-in-use");

        currencyIdToAddress[currency] = currencyAddress;
        currencyAddressToId[currencyAddress] = currency;
        emit CurrencyAdded(currency, currencyAddress);
    }

    function addPool(uint64 poolId) public onlyGateway {
        Pool storage pool = pools[poolId];
        require(pool.createdAt == 0, "CentrifugeConnector/pool-already-added");
        pool.poolId = poolId;
        pool.createdAt = block.timestamp;
        pool.isActive = true;
        emit PoolAdded(poolId);
    }

    function allowPoolCurrency(uint64 poolId, uint128 currency) public onlyGateway {
        Pool storage pool = pools[poolId];
        require(pool.createdAt > 0, "CentrifugeConnector/invalid-pool");

        address currencyAddress = currencyIdToAddress[currency];
        require(currencyAddress != address(0), "CentrifugeConnector/unknown-currency");

        allowedPoolCurrencies[poolId][currencyAddress] = true;
        emit PoolCurrencyAllowed(currency, poolId);
    }

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
        address token = liquidityPools[_poolId][_trancheId];
        require(token != address(0), "CentrifugeConnector/invalid-pool-or-tranche");
        LiquidityPoolLike(token).updateTokenPrice(_price);
    }

    function updateMember(uint64 _poolId, bytes16 _trancheId, address _user, uint64 _validUntil) public onlyGateway {
        LiquidityPoolLike tranche = LiquidityPoolLike(liquidityPools[_poolId][_trancheId]);
        require(address(tranche) != address(0), "CentrifugeConnector/invalid-pool-or-tranche");
        MemberlistLike memberlist = MemberlistLike(tranche.memberlist());
        memberlist.updateMember(_user, _validUntil);
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

    function handleTransferTrancheTokens(uint64 _poolId, bytes16 _trancheId, address _destinationAddress, uint128 _amount)
        public
        onlyGateway
    {
        LiquidityPoolLike tranche = LiquidityPoolLike(liquidityPools[_poolId][_trancheId]);
        require(address(tranche) != address(0), "CentrifugeConnector/unknown-token");

        require(tranche.hasMember(_destinationAddress), "CentrifugeConnector/not-a-member");
        tranche.mint(_destinationAddress, _amount);
    }

    function handleDecreaseInvestOrder(uint64 _poolId, bytes16 _trancheId, address _user, uint128 _currency, uint128 _currencyPayout, uint128 _remainingInvestOrder) public onlyGateway {
        require(_currencyPayout != 0, "CentrifugeConnector/zero-payout");
        address currencyAddress = currencyIdToAddress[_currency];
        LiquidityPoolLike tranche = LiquidityPoolLike(liquidityPools[_poolId][_trancheId]);
        require(address(tranche) != address(0), "CentrifugeConnector/tranche-does-not-exist");
        require(allowedPoolCurrencies[_poolId][currencyAddress], "CentrifugeConnector/pool-currency-not-allowed");
        require(currencyAddress != address(0), "CentrifugeConnector/unknown-currency");
        require(currencyAddress == tranche.asset(), "CentrifugeConnector/not-tranche-currency");

        // TODO: escrow should give max approval on deployment
        EscrowLike(escrow).approve(currencyAddress, address(this), _currencyPayout);
   
        require(
            ERC20Like(currencyAddress).transferFrom(address(escrow), _user, _currencyPayout),
            "CentrifugeConnector/currency-transfer-failed"
        );
        orderbook[_user][address(tranche)].openInvest = _remainingInvestOrder;
    }

    function handleDecreaseRedeemOrder(uint64 _poolId, bytes16 _trancheId, address _user, uint128 _currency, uint128 _tokensPayout, uint128 _remainingRedeemOrder) public onlyGateway {
        require(_tokensPayout != 0, "CentrifugeConnector/zero-payout");
        LiquidityPoolLike tranche = LiquidityPoolLike(liquidityPools[_poolId][_trancheId]);
        require(address(tranche) != address(0), "CentrifugeConnector/tranche-does-not-exist");
       
        require(LiquidityPoolLike(tranche).hasMember(_user), "CentrifugeConnector/not-a-member");
        // TODO: escrow should give max approval on deployment
        EscrowLike(escrow).approve(address(tranche), address(this), _tokensPayout);
        require(
            tranche.transferFrom(address(escrow), _user, _tokensPayout),
            "CentrifugeConnector/trancheTokens-transfer-failed"
        );
        orderbook[_user][address(tranche)].openRedeem = _remainingRedeemOrder;
    }

    function handleCollectInvest(uint64 _poolId, bytes16 _trancheId, address _recepient, uint128 _currency, uint128 _currencyInvested, uint128 _tokensPayout, uint128 _remainingInvestOrder) public onlyGateway {
        require(_currencyInvested != 0, "CentrifugeConnector/zero-invest");
        address tranche = liquidityPools[_poolId][_trancheId];
        require(tranche != address(0), "CentrifugeConnector/tranche-does-not-exist");
        
        LPValues memory values = orderbook[_recepient][tranche];
        values.openInvest = _remainingInvestOrder;
        values.maxDeposit = values.maxDeposit + _currencyInvested;
        values.maxMint = values.maxMint + _tokensPayout;

        LiquidityPoolLike(tranche).mint(address(escrow), _tokensPayout); // mint to escrow. Recepeint can claim by calling withdraw / redeem
    }

    function handleCollectRedeem(uint64 _poolId, bytes16 _trancheId, address _recepient, uint128 _currency, uint128 _currencyPayout, uint128 _trancheTokensRedeemed, uint128 _remainingRedeemOrder) public onlyGateway {
        require(_trancheTokensRedeemed != 0, "CentrifugeConnector/zero-redeem");
        address tranche = liquidityPools[_poolId][_trancheId];
        require(tranche != address(0), "CentrifugeConnector/tranche-does-not-exist");
        
        LPValues memory values = orderbook[_recepient][tranche];
        values.openRedeem = _remainingRedeemOrder;
        values.maxWithdraw = values.maxWithdraw + _currencyPayout;
        values.maxRedeem = values.maxRedeem + _trancheTokensRedeemed;

        LiquidityPoolLike(tranche).burn(address(escrow), _trancheTokensRedeemed); // burned redeemed tokens from escrow
    } 

    // ----- public functions

    function deployLiquidityPool(   
        uint64 _poolId,
        bytes16 _trancheId,
        address _currency
        ) public returns (address) {

        address liquidityPool = liquidityPools[_poolId][_trancheId][_currency];
        require(liquidityPool == address(0), "CentrifugeConnector/liquidityPool-already-deployed");
        Tranche storage tranche = tranches[_poolId][_trancheId];
        require(tranche.createdAt != 0, "CentrifugeConnector/tranche-does-not-exist"); // tranche must have been added
        require(_poolCurrencyCheck(_poolId, _currency), "CentrifugeConnector/currency-not-supported"); // currency must be supported by pool
        uint128 currencyId = currencyAddressToId[_currency];
         // gateway admin on liquidityPool
        liquidityPool = liquidityPoolFactory.newLiquidityPool(_poolId, _trancheId, currencyId, _currency, address(this), address(gateway), tranche.tokenName, tranche.tokenSymbol, tranche.decimals);
        
        liquidityPools[_poolId][_trancheId][_currency] = liquidityPool;
        LiquidityPoolInfo storage lPoolInfo = addressToLiquidityPoolInfo[liquidityPool];
        lPoolInfo.poolId = _poolId;
        lPoolInfo.trancheId = _trancheId;

        address memberlist = memberlistFactory.newMemberlist(address(gateway)); // gateway admin on memberlist
        LiquidityPoolLike(liquidityPool).file("memberlist", memberlist);
        MemberlistLike(memberlist).updateMember(address(escrow), type(uint256).max); // add escrow to tranche tokens memberlist

        emit LiquidityPoolDeployed(_poolId, _trancheId, liquidityPool);
        return liquidityPool;
    }
                                
     // ------ helper functions 
    function calcCustomTrancheTokenPrice(address _user, address _liquidityPool) public view returns (uint128 userTrancheTokenPrice) {
        LPValues memory lpValues = orderbook[_user][_liquidityPool];
        if(lpValues.maxMint == 0) {
            return 0;
        }
        userTrancheTokenPrice = lpValues.maxDeposit / lpValues.maxMint;
    }

    function _poolCurrencyCheck(uint64 _poolId, address _currencyAddress) internal view returns (bool) {
        uint128 currency = currencyAddressToId[_currencyAddress];
        require(currency != 0, "CentrifugeConnector/unknown-currency");
        require(allowedPoolCurrencies[_poolId][_currencyAddress], "CentrifugeConnector/pool-currency-not-allowed");
        return true;
    }
    
    function _trancheTokenCheck(uint64 _poolId, bytes16 _trancheId, address _user) internal returns (bool) {
        LiquidityPoolLike tranche = LiquidityPoolLike(liquidityPools[_poolId][_trancheId]);
        require(address(tranche) != address(0), "CentrifugeConnector/unknown-tranche-token");
        require(tranche.hasMember(_user), "CentrifugeConnector/not-a-member");
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
    function _toUint128(uint256 _value) internal returns (uint128 value) {
        if (_value > 2 ** 128) {
            revert();
        } else {
            value = uint128(_value);
        }
    }
}
