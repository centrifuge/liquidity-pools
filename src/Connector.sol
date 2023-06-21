// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.18;
pragma abicoder v2;

import {TrancheTokenFactoryLike, MemberlistFactoryLike} from "./token/factory.sol";
import {RestrictedTokenLike, ERC20Like} from "./token/restricted.sol";
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

// is RestrictedToken
interface TrancheLike {
    function updateTokenPrice(uint128 _tokenPrice) external;
    function asset() external returns (address);
    function mint(address, uint) external;
    function balanceOf(address) external returns (uint);
    function  transferFrom(address, address, uint) external;
}

interface EscrowLike {
    function approve(address token, address spender, uint256 value) external;
}

struct Pool {
    uint64 poolId;
    uint256 createdAt;
    bool isActive;
}

struct Tranche {
    address token;
    address asset;
}

struct CFGTranche {
    uint64 poolId;
    bytes16 trancheId;
}

struct UserTrancheValues {
    uint256 maxDeposit;
    uint256 maxMint;
    uint256 maxWithdraw;
    uint256 maxRedeem;
    uint256 openRedeem;
    uint256 openInvest;
}

contract CentrifugeConnector is Auth {

    mapping(uint64 => Pool) public pools;
    mapping(uint64 => mapping(bytes16 => address)) public tranches;
    mapping(address => CFGTranche) public cfgTranches; // maps evm tranches to CFG tranches
    mapping(address => mapping(address => UserTrancheValues)) public orderbook; // contains outstanding orders and limits for each user and tranche

    mapping(uint128 => address) public currencyIdToAddress;
    // The reverse mapping of `currencyIdToAddress`
    mapping(address => uint128) public currencyAddressToId;

    mapping(uint64 => mapping(address => bool)) public allowedPoolCurrencies;

    GatewayLike public gateway;
    EscrowLike public immutable escrow;

    TrancheTokenFactoryLike public immutable tokenFactory;
    MemberlistFactoryLike public immutable memberlistFactory;

    // --- Events ---
    event File(bytes32 indexed what, address data);
    event CurrencyAdded(uint128 indexed currency, address indexed currencyAddress);
    event PoolAdded(uint256 indexed poolId);
    event PoolCurrencyAllowed(uint128 currency, uint64 poolId);
    event TrancheAdded(uint256 indexed poolId, bytes16 indexed trancheId);
    event TrancheDeployed(uint256 indexed poolId, bytes16 indexed trancheId, address indexed token);

    constructor(address escrow_, address tokenFactory_, address memberlistFactory_) {
        escrow = EscrowLike(escrow_);
        tokenFactory = TrancheTokenFactoryLike(tokenFactory_);
        memberlistFactory = MemberlistFactoryLike(memberlistFactory_);

        wards[msg.sender] = 1;
        emit Rely(msg.sender);
    }

    modifier poolActive(address _tranche) {
        CFGTranche cfgTranche = cfgTranches[_tranche];
        require(pools[cfgTranche.poolId].isActive, "CentrifugeConnector/pool-deactivated");
        _;
    }

    modifier connectorsActive() {
        require(gateway.active(), "CentrifugeConnector/connectors-deactivated");
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

    // --- Outgoing message handling ---
    // auth functions
    function processDeposit(address _tranche, address _user, uint256 _currencyAmount) public poolActive(_tranche) connectorsActive auth returns (uint256) {
        require((_currencyAmount <= orderbook[_user][_tranche].maxDeposit), "CentrifugeConnector/amount-exceeds-deposit-limits");
        uint256 userTrancheTokenPrice = calcCustomTrancheTokenPrice( _user, _tranche);
        require((userTrancheTokenPrice > 0), "Tranche4626/amount-exceeds-deposit-limits");
        uint256 trancheTokensPayout = _currencyAmount / userTrancheTokenPrice;
        _decreaseDepositLimits(_user, _tranche, _currencyAmount, trancheTokensPayout); // decrease the possible deposit limits
        require(ERC20Like(_tranche).transferFrom(address(escrow), _user, trancheTokensPayout), "CentrifugeConnector/trancheTokens-transfer-failed");
        return trancheTokensPayout;
    }

    function processMint(address _tranche, address _user, uint256 _trancheTokensAmount) public poolActive(_tranche) connectorsActive auth returns (uint256) {
        require((_trancheTokensAmount <= orderbook[_user][_tranche].maxMint), "CentrifugeConnector/amount-exceeds-mint-limits");
        uint256 userTrancheTokenPrice = calcCustomTrancheTokenPrice( _user, _tranche);
        require((userTrancheTokenPrice > 0), "Tranche4626/amount-exceeds-mint-limits");
        uint256 currencyDeposited = _trancheTokensAmount * userTrancheTokenPrice;
        _decreaseDepositLimits(_user, _tranche, currencyDeposited, _trancheTokensAmount); // decrease the possible deposit limits
        require(ERC20Like(_tranche).transferFrom(address(escrow), _user, _trancheTokensAmount), "CentrifugeConnector/shares-transfer-failed");
        return currencyDeposited;
    }

    function processWithdraw(address _tranche, uint256 _currencyAmount, address _receiver, address _user) public poolActive(_tranche) connectorsActive auth returns (uint256) {
        require((_currencyAmount <= orderbook[_user][_tranche].maxWithdaw), "CentrifugeConnector/amount-exceeds-withdraw-limits");
        TrancheLike tranche = TrancheLike(_tranche);
        uint256 userTrancheTokenPrice = calcCustomTrancheTokenPrice(_user, _tranche);
        require((userTrancheTokenPrice > 0), "Tranche4626/amount-exceeds-withdraw-limits");
        uint256 redeemedTrancheTokens = _currencyAmount / userTrancheTokenPrice;
        _decreaseRedemptionLimits(_user, _tranche, _currencyAmount, redeemedTrancheTokens);
        require(ERC20Like(tranche.asset()).transferFrom(address(escrow), _receiver, _currencyAmount), "CentrifugeConnector/trancheTokens-transfer-failed");
        return redeemedTrancheTokens;
    }

    function processRedeem(address _tranche, uint256 _trancheTokensAmount, address _receiver, address _user) public poolActive(_tranche) connectorsActive auth returns (uint256) {
        require((_trancheTokensAmount <= orderbook[_user][_tranche].maxRedeem), "CentrifugeConnector/amount-exceeds-redeem-limits");
        uint256 userTrancheTokenPrice = calcCustomTrancheTokenPrice( _user, _tranche);
        require((userTrancheTokenPrice > 0), "Tranche4626/amount-exceeds-redemption-limits");
        uint256 currencyPayout = _trancheTokensAmount * userTrancheTokenPrice;
        _decreaseRedemptionLimits(_user, _tranche, currencyPayout, _trancheTokensAmount); // decrease the possible deposit limits
        require(ERC20Like(_tranche).transferFrom(address(escrow), _receiver, currencyPayout), "CentrifugeConnector/shares-transfer-failed");
        return currencyPayout;
    }

    function requestRedeem(address _tranche, uint256 _trancheTokensAmount, address _user) connectorsActive poolActive(_tranche) public auth {
        UserTrancheValues userValues = orderbook[_user][_tranche];
        CFGTranche cfgTranche = cfgTranches[_tranche];
        TrancheLike tranche = TrancheLike(_tranche);

        require(_poolCurrencyCheck(tranche.asset(), cfgTranche.poolId), "CentrifugeConnector/currency-not-supported");
        require(_trancheTokenCheck(cfgTranche.poolId, cfgTranche.trancheId, _user), "CentrifugeConnector/tranche-tokens-not-supported");
       
        if (userValues.openDeposit > 0) { // cancel outstanding deposit orders 
            // replace
           gateway.decreaseInvestOrder(cfgTranche.poolId, cfgTranche.trancheId, _user, tranche.asset(), userValues.openDeposit);
        }
        if(_trancheTokensAmount == 0) { // case: user justwants to cancel outstanding orders
            return;
        }

        if(userValues.maxMint >= _trancheTokensAmount) { // case: user has unclaimed trancheTokens in escrow -> more than redemption request
            uint256 userTrancheTokenPrice = calcCustomTrancheTokenPrice( _user, _tranche);
            uint256 assets = _trancheTokensAmount * userTrancheTokenPrice;
            _decreaseDepositLimits(_user, _tranche, assets, _trancheTokensAmount);
        } else {
            uint transferAmount = _trancheTokensAmount - userValues.maxMint;
            userValues.maxDeposit = 0;
            userValues.maxMint = 0;

            require(tranche.balanceOf(_user) >= _trancheTokensAmount, "CentrifugeConnector/insufficient-tranche-token-balance");
            require(tranche.transferFrom(_user, address(escrow), transferAmount), "CentrifugeConnector/tranche-token-transfer-failed");
        } 

        gateway.increaseRedeemOrder(cfgTranche.poolId, cfgTranche.trancheId, _user, tranche.asset(), _trancheTokensAmount);
    }
    

    // TODO: fix uint256 - uint128
    function requestDeposit(address _tranche, uint _currencyAmount, address _user) connectorsActive poolActive(_tranche) public auth {
        UserTrancheValues userValues = orderbook[_user][_tranche];
        CFGTranche cfgTranche = cfgTranches[_tranche];
        TrancheLike tranche = TrancheLike(_tranche);
        ERC20Like currency = ERC20Like(TrancheLike(_tranche).asset());

        require(_poolCurrencyCheck(tranche.asset(), cfgTranche.poolId), "CentrifugeConnector/currency-not-supported");
        require(_trancheTokenCheck(cfgTranche.poolId, cfgTranche.trancheId, _user), "CentrifugeConnector/tranche-tokens-not-supported");

        if (userValues.openRedeem > 0) { // cancel outstanding redeem orders 
            gateway.decreaseRedeemOrder(cfgTranche.poolId, cfgTranche.trancheId, _user, tranche.asset(), userValues.openRedeem);
        }
        if(_currencyAmount == 0) { // case: user only wants to cancel outstanding redemptions
            return; 
        }
        if(userValues.maxWithdraw >= _currencyAmount) { // case: user has some claimable fund in escrow -> funds > Deposit request
            uint256 userTrancheTokenPrice = calcCustomTrancheTokenPrice( _user, _tranche);
            uint256 trancheTokens = _currencyAmount / userTrancheTokenPrice;
            _decreaseRedemptionLimits(_user, _tranche, _currencyAmount, trancheTokens);
        } else {
            uint transferAmount = _currencyAmount - userValues.maxWithdraw;
            userValues.maxWithdraw = 0;
            userValues.maxRedeem = 0;

            require(currency.balanceOf(_user) >= transferAmount, "CentrifugeConnector/insufficient-balance");
            require(currency.transferFrom(_user, address(escrow), transferAmount), "CentrifugeConnector/currency-transfer-failed");
        } 

        gateway.increaseInvestOrder(cfgTranche.poolId, cfgTranche.trancheId, _user, tranche.asset(), _currencyAmount);
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
        RestrictedTokenLike token = RestrictedTokenLike(tranches[poolId][trancheId]);
        require(address(token) != address(0), "CentrifugeConnector/unknown-token");

        require(token.balanceOf(msg.sender) >= amount, "CentrifugeConnector/insufficient-balance");
        token.burn(msg.sender, amount);

        gateway.transferTrancheTokensToCentrifuge(poolId, trancheId, msg.sender, destinationAddress, amount);
    }

    function transferTrancheTokensToEVM(
        uint64 poolId,
        bytes16 trancheId,
        uint64 destinationChainId,
        address destinationAddress,
        uint128 amount
    ) public {
        RestrictedTokenLike token = RestrictedTokenLike(tranches[poolId][trancheId]);
        require(address(token) != address(0), "CentrifugeConnector/unknown-token");

        require(token.balanceOf(msg.sender) >= amount, "CentrifugeConnector/insufficient-balance");
        token.burn(msg.sender, amount);

        gateway.transferTrancheTokensToEVM(
            poolId, trancheId, msg.sender, destinationChainId, destinationAddress, amount
        );
    }

    // function increaseInvestOrder(uint64 _poolId, bytes16 _trancheId, address _currencyAddress, uint128 _amount ) public {
    //      _increaseInvestOrder(_poolId, _trancheId, _currencyAddress, _amount, msg.sender);
    // }

    // function _increaseInvestOrder(uint64 _poolId, bytes16 _trancheId, address _currencyAddress, uint128 _amount, address _user) internal {
    //     RestrictedTokenLike token = RestrictedTokenLike(tranches[_poolId][_trancheId]);
    //     require(address(token) != address(0), "CentrifugeConnector/unknown-tranche-token");
    //     require(token.hasMember(_user), "CentrifugeConnector/not-a-member");

    //     uint128 currency = currencyAddressToId[_currencyAddress];
    //     require(currency != 0, "CentrifugeConnector/unknown-currency");
    //     require(allowedPoolCurrencies[_poolId][_currencyAddress], "CentrifugeConnector/pool-currency-not-allowed");

    //     require(
    //         ERC20Like(_currencyAddress).transferFrom(_user, address(escrow), _amount),
    //         "Centrifuge/Connector/currency-transfer-failed"
    //     );

    //     gateway.increaseInvestOrder(_poolId, _trancheId, _user, currency, _amount);
    // }

    // function decreaseInvestOrder(uint64 _poolId, bytes16 _trancheId, address _currencyAddress, uint128 _amount) public {
    //     _decreaseInvestOrder(_poolId, _trancheId, _currencyAddress, _amount, msg.sender);
    // }

    // function _decreaseInvestOrder(uint64 poolId, bytes16 _trancheId, address _currencyAddress, uint128 _amount, address _user) public {
    //     // RestrictedTokenLike token = RestrictedTokenLike(tranches[poolId][_trancheId].token);
    //     // require(address(token) != address(0), "CentrifugeConnector/unknown-tranche-token");
    //     // require(token.hasMember(_user), "CentrifugeConnector/not-a-member");

    //     uint128 currency = currencyAddressToId[_currencyAddress];
    //     require(currency != 0, "CentrifugeConnector/unknown-currency");
    //     require(allowedPoolCurrencies[poolId][_currencyAddress], "CentrifugeConnector/pool-currency-not-allowed");

    //     gateway.decreaseInvestOrder(poolId, _trancheId, _user, currency, _amount);
    // }

    // function increaseRedeemOrder(uint64 _poolId, bytes16 _trancheId, address _currencyAddress, uint128 _amount) public {
    //    _increaseRedeemOrder(_poolId, _trancheId, _currencyAddress, _amount, msg.sender);
    // }

    // function _increaseRedeemOrder(uint64 _poolId, bytes16 _trancheId, address _currencyAddress, uint128 _amount, address _user) internal {
    //     RestrictedTokenLike token = RestrictedTokenLike(tranches[_poolId][_trancheId]);
    //     require(address(token) != address(0), "CentrifugeConnector/unknown-tranche-token");
    //     require(token.hasMember(_user), "CentrifugeConnector/not-a-member");

    //     uint128 currency = currencyAddressToId[_currencyAddress];
    //     require(currency != 0, "CentrifugeConnector/unknown-currency");
    //     require(allowedPoolCurrencies[_poolId][_currencyAddress], "CentrifugeConnector/pool-currency-not-allowed");

    //     gateway.increaseRedeemOrder(_poolId, _trancheId, _user, currency, _amount);
    // }

    // function decreaseRedeemOrder(uint64 _poolId, bytes16 _trancheId, address _currencyAddress, uint128 _amount) public {
    //     _decreaseRedeemOrder(_poolId, _trancheId, _currencyAddress, _amount, msg.sender);    
    // }

    // function _decreaseRedeemOrder(uint64 _poolId, bytes16 _trancheId, address _currencyAddress, uint128 _amount, address _user) internal {
    //     RestrictedTokenLike token = RestrictedTokenLike(tranches[_poolId][_trancheId]);
    //     require(address(token) != address(0), "CentrifugeConnector/unknown-tranche-token");
    //     require(token.hasMember(_user), "CentrifugeConnector/not-a-member");

    //     uint128 currency = currencyAddressToId[_currencyAddress];
    //     require(currency != 0, "CentrifugeConnector/unknown-currency");
    //     require(allowedPoolCurrencies[_poolId][_currencyAddress], "CentrifugeConnector/pool-currency-not-allowed");

    //     gateway.decreaseRedeemOrder(_poolId, _trancheId, _user, currency, _amount);
    // }

    function collectInvest(uint64 _poolId, bytes16 _trancheId) public {
        RestrictedTokenLike token = RestrictedTokenLike(tranches[_poolId][_trancheId]);
        require(address(token) != address(0), "CentrifugeConnector/unknown-tranche-token");
        require(token.hasMember(msg.sender), "CentrifugeConnector/not-a-member");

        gateway.collectInvest(_poolId, _trancheId, address(msg.sender));
    }

    function collectRedeem(uint64 _poolId, bytes16 _trancheId) public {
        RestrictedTokenLike token = RestrictedTokenLike(tranches[_poolId][_trancheId]);
        require(address(token) != address(0), "CentrifugeConnector/unknown-tranche-token");
        require(token.hasMember(msg.sender), "CentrifugeConnector/not-a-member");

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
        uint128 _price
    ) public onlyGateway {
        Pool storage pool = pools[_poolId];
        require(pool.createdAt > 0, "CentrifugeConnector/invalid-pool");

        address tranche = tranches[_poolId][_trancheId];
        require(tranche == address(0), "CentrifugeConnector/tranche-already-added");
        address asset = address(0x6B175474E89094C44Da98b954EedeAC495271d0F); // TODO FIX : provide tranche currency / assets : default DAI?
        tranche = deployTranche(_poolId, _trancheId, asset, _tokenName, _tokenSymbol, _decimals);
        TrancheLike(tranche).updateTokenPrice(_price);

        // update multi-chain tranche mappings
        tranches[_poolId][_trancheId] = tranche;
        CFGTranche storage cfgTranche = cfgTranches[_poolId][_trancheId];
        cfgTranche.poolId = _poolId;
        cfgTranche.trancheId = _trancheId;

        emit TrancheAdded(_poolId, _trancheId);
    }

    function updateTokenPrice(uint64 _poolId, bytes16 _trancheId, uint128 _price) public onlyGateway {
        address token = tranches[_poolId][_trancheId];
        require(token != address(0), "CentrifugeConnector/invalid-pool-or-tranche");
        TrancheLike(token).updateTokenPrice(_price);
    }

    function updateMember(uint64 poolId, bytes16 trancheId, address user, uint64 validUntil) public onlyGateway {
        address token = tranches[_poolId][_trancheId];
        require(token != address(0), "CentrifugeConnector/invalid-pool-or-tranche");
        RestrictedTokenLike trancheToken = RestrictedTokenLike(tranche.token);
        MemberlistLike memberlist = RestrictedTokenLike(token).memberlist();
        memberlist.updateMember(user, validUntil);
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

    function handleTransferTrancheTokens(uint64 poolId, bytes16 trancheId, address destinationAddress, uint128 amount)
        public
        onlyGateway
    {
        RestrictedTokenLike token = RestrictedTokenLike(tranches[poolId][trancheId]);
        require(address(token) != address(0), "CentrifugeConnector/unknown-token");

        require(token.hasMember(destinationAddress), "CentrifugeConnector/not-a-member");
        token.mint(destinationAddress, amount);
    }

    function handleDecreaseInvestOrder(uint64 _poolId, bytes16 _trancheId, address _user, uint128 _currency, uint128 _currencyPayout, uint128 _remainingInvestOrder) public onlyGateway {
        require(_currencyPayout != 0, "CentrifugeConnector/zero-payout");
        address currencyAddress = currencyIdToAddress[_currency];
        address tranche = tranches[_poolId][_trancheId];
        require(tranche != address(0), "CentrifugeConnector/tranche-does-not-exist");
        require(allowedPoolCurrencies[_poolId][currencyAddress], "CentrifugeConnector/pool-currency-not-allowed");
        require(currencyAddress != address(0), "CentrifugeConnector/unknown-currency");
        require(currencyAddress == TrancheLike(tranche).asset(), "CentrifugeConnector/not-tranche-currency");

        // TODO: escrow should give max approval on deployment
        EscrowLike(escrow).approve(currencyAddress, address(this), _currencyPayout);
   
        require(
            ERC20Like(currencyAddress).transferFrom(address(escrow), _user, _currencyPayout),
            "CentrifugeConnector/currency-transfer-failed"
        );
        orderbook[_user][tranche].openInvest = _remainingInvestOrder;
    }

    //TODO: currency not really required here
    function handleDecreaseRedeemOrder(uint64 _poolId, bytes16 _trancheId, address _user, uint128 _currency, uint128 _tokensPayout, uint128 _remainingRedeemOrder) public onlyGateway {
        require(_tokensPayout != 0, "CentrifugeConnector/zero-payout");
        address tranche = tranches[poolId][trancheId];
        require(tranche != address(0), "CentrifugeConnector/tranche-does-not-exist");

        require(RestrictedTokenLike(tranche).hasMember(_user), "CentrifugeConnector/not-a-member");
        // TODO: escrow should give max approval on deployment
        EscrowLike(escrow).approve(tranche, address(this), _tokensPayout);
        require(
            ERC20Like(tranche).transferFrom(address(escrow), _user, _tokensPayout),
            "CentrifugeConnector/trancheTokens-transfer-failed"
        );
        orderbook[_user][tranche].openRedeem = _remainingRedeemOrder;
    }

    function handleCollectInvest(uint64 _poolId, bytes16 _trancheId, address _recepient, uint128 _currency, uint128 _currencyInvested, uint128 _tokensPayout, uint128 _remainingInvestOrder) public onlyGateway {
        require(_currencyInvested != 0, "CentrifugeConnector/zero-invest");
        address tranche = tranches[_poolId][_trancheId];
        require(tranche != address(0), "CentrifugeConnector/tranche-does-not-exist");
        
        UserTrancheValues values = orderbook[_recepient][tranche];
        values.openInvest = _remainingInvestOrder;
        values.maxDeposit = values.maxDeposit + _currencyInvested;
        values.maxMint = values.maxMint + _tokensPayout;

        TrancheLike(tranche).mint(address(escrow), _tokensPayout); // mint to escrow. Recepeint can claim by calling withdraw / redeem
    }

    function handleCollectRedeem(uint64 _poolId, bytes16 _trancheId, address _recepient, uint128 _currency, uint128 _currencyPayout, uint128 _trancheTokensRedeemed, uint128 _remainingRedeemOrder) public onlyGateway {
        require(_trancheTokensRedeemed != 0, "CentrifugeConnector/zero-redeem");
        address tranche = tranches[_poolId][_trancheId];
        require(tranche != address(0), "CentrifugeConnector/tranche-does-not-exist");
        
        UserTrancheValues values = orderbook[_recepient][tranche];
        values.openRedeem = _remainingRedeemOrder;
        values.maxWithdraw = values.maxWithdraw + _currencyPayout;
        values.maxRedeem = values.maxRedeem + _trancheTokensRedeemed;

        TrancheLike(tranche).burn(address(escrow), _trancheTokensRedeemed); // burned redeemed tokens from escrow
    }

    // ------ internal helper functions 

    //TODO: rounding 

    function _poolCurrencyCheck(uint64 _poolId, address _currencyAddress) internal returns (bool) {
        uint128 currency = currencyAddressToId[_currencyAddress];
        require(currency != 0, "CentrifugeConnector/unknown-currency");
        require(allowedPoolCurrencies[_poolId][_currencyAddress], "CentrifugeConnector/pool-currency-not-allowed");
        return true;
    }
    
    function _trancheTokenCheck(uint64 _poolId, bytes16 _trancheId, address _user) internal returns (bool) {
        RestrictedTokenLike token = RestrictedTokenLike(tranches[_poolId][_trancheId]);
        require(address(token) != address(0), "CentrifugeConnector/unknown-tranche-token");
        require(token.hasMember(_user), "CentrifugeConnector/not-a-member");
        return true;
    }

    function _decreaseDepositLimits(address _user, address _tranche, uint256 _currency, uint256 _trancheTokens) internal {
        UserTrancheValues values = orderbook[_user][_tranche];
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

    function _decreaseRedemptionLimits(address _user, address _tranche, uint256 _currency, uint256 _trancheTokens) internal {
        UserTrancheValues values = orderbook[_user][_tranche];
        if (values.maxWithdrawel < _currency) {
            values.maxDeposit = 0;
        } else {
            values.maxWithdrawel = values.maxWithdrawel - _currency;
        }
        if (values.maxRedemption < _trancheTokens) {
            values.maxRedemption = 0;
        } else {
             values.maxRedemption = values.maxRedemption - _trancheTokens;
        }
    }


    // TODO: ward setup on tranche contract
    function deployTranche(
        uint64 _poolId,
        bytes16 _trancheId,
        address _asset, 
        uint8 _decimals,
        string memory _tokenName,
        string memory _tokenSymbol) internal returns (address) {
            require(tranches[_poolId][_trancheId] == address(0), "CentrifugeConnector/tranche-already-deployed");
            address token = deployTranche(_asset, address(this), _decimals, _tokenName, _tokenSymbol); // TODO: use factory 
            tranches[_poolId][_trancheId] = token;

            address memberlist = memberlistFactory.newMemberlist();
            RestrictedTokenLike(token).file("memberlist", memberlist);
            MemberlistLike(memberlist).updateMember(address(escrow), type(uint256).max); // add escrow to tranche tokens memberlist
            emit TrancheDeployed(poolId, trancheId, token);
    }

    // ------ EIP 4626 view functions
   
    /// @dev calculates the avg share price for the deposited assets of a specific user
    function calcCustomTrancheTokenPrice(address _user, address _tranche) public view returns (uint256 userTrancheTokenPrice) {
        UserTrancheValues values = orderbook[_user][_tranche];
        if(values.maxMint == 0) {
            return 0;
        }
        userTrancheTokenPrice = values.maxDeposit / values.maxMint;
    }

    function maxDeposit(address _user, address _tranche) public view returns (uint256) {
        return orderbook[_user][_tranche].maxDeposit;
    }

    function maxMint(address _user, address _tranche) public view returns (uint256) {
        return orderbook[_user][_tranche].maxMint;
    }

    function maxWithdraw(address _user, address _tranche) public view returns (uint256) {
        return orderbook[_user][_tranche].maxWithdraw;
    }

    function maxRedeem(address _user, address _tranche) public view returns (uint256) {
        return orderbook[_user][_tranche].maxRedeem;
    }   
}
