pragma solidity ^0.8.18;
pragma abicoder v2;

import {LiquidityPoolFactoryLike, MemberlistFactoryLike} from "./liquidityPool/Factory.sol";
import {LiquidityPool, LiquidityPoolLike} from "./liquidityPool/LiquidityPool.sol";
import {ERC20Like} from "./token/restricted.sol";
import {MemberlistLike} from "./token/memberlist.sol";
import {GatewayLike} from "./gateway.sol";
import "./auth/auth.sol";

interface EscrowLike {
    function approve(address token, address spender, uint256 value) external;
}

struct Pool {
    uint64 poolId;
    uint256 createdAt;
    bool isActive;
}

struct Tranche {
    uint64 poolId;
    bytes16 trancheId;
    uint8 decimals;
    uint256 createdAt;
    string tokenName;
    string tokenSymbol;
    address[] liquidityPools;
}

struct LPValues {
    uint128 maxDeposit;
    uint128 maxMint;
    uint128 maxWithdraw;
    uint128 maxRedeem;
}

contract InvestmentManager is Auth {
    mapping(uint64 => Pool) public pools;
    mapping(uint64 => mapping(bytes16 => Tranche)) public tranches;
    mapping(uint64 => mapping(bytes16 => mapping(address => address))) public liquidityPools;
    mapping(address => uint256) public liquidityPoolWards;
    mapping(address => mapping(address => LPValues)) public orderbook;

    mapping(uint128 => address) public currencyIdToAddress;
    mapping(address => uint128) public currencyAddressToId;
    mapping(uint64 => mapping(address => bool)) public allowedPoolCurrencies;

    GatewayLike public gateway;
    EscrowLike public immutable escrow;

    LiquidityPoolFactoryLike public immutable liquidityPoolFactory;
    MemberlistFactoryLike public immutable memberlistFactory;

    uint256 constant MAX_UINT256 = type(uint256).max;
    uint128 constant MAX_UINT128 = type(uint128).max;

    event File(bytes32 indexed what, address data);
    event CurrencyAdded(uint128 indexed currency, address indexed currencyAddress);
    event PoolAdded(uint64 indexed poolId);
    event PoolCurrencyAllowed(uint128 indexed currency, uint64 indexed poolId);
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

    function getLiquidityPoolsForTranche(uint64 _poolId, bytes16 _trancheId) public view returns (address[] memory lPools) {
        lPools = tranches[_poolId][_trancheId].liquidityPools; 
    }

    modifier poolActive() {
        LiquidityPoolLike lPool = LiquidityPoolLike(msg.sender);
        require(pools[lPool.poolId()].isActive, "IM/pool-deactivated");
        _;
    }

    modifier gatewayActive() {
        require(!gateway.paused(), "IM/investmentManager-deactivated");
        _;
    }

    modifier onlyGateway() {
        require(msg.sender == address(gateway), "IM/not-the-gateway");
        _;
    }

    modifier onlyLiquidityPoolWard() {
        require(liquidityPoolWards[msg.sender] == 1, "IM/not-liquidity-pool");
        _;
    }

    function file(bytes32 what, address data) external auth {
        if (what == "gateway") gateway = GatewayLike(data);
        else revert("IM/file-unrecognized-param");
        emit File(what, data);
    }

    function setPoolActive(uint64 _poolId, bool _isActive) external auth {
        Pool storage pool = pools[_poolId];
        require(pool.createdAt > 0, "IM/invalid-pool");
        pool.isActive = _isActive;
    }

    function requestRedeem(uint256 _trancheTokenAmount, address _user)
        public
        poolActive
        gatewayActive
        onlyLiquidityPoolWard
    {
        address _liquidityPool = msg.sender;
        LPValues storage lpValues = orderbook[_user][_liquidityPool];
        LiquidityPoolLike lPool = LiquidityPoolLike(_liquidityPool);
        uint128 trancheTokenAmount = _toUint128(_trancheTokenAmount);

        require(_poolCurrencyCheck(lPool.poolId(), lPool.asset()), "IM/currency-not-supported");
        require(
            _liquidityPoolTokensCheck(lPool.poolId(), lPool.trancheId(), lPool.asset(), _user),
            "IM/tranche-tokens-not-supported"
        );

        if (trancheTokenAmount == 0) {
            return;
        }

        if (lpValues.maxMint >= trancheTokenAmount) {
            uint128 userTrancheTokenPrice = calcDepositTrancheTokenPrice(_user, _liquidityPool);
            uint128 currencyAmount = trancheTokenAmount * userTrancheTokenPrice;
            _decreaseDepositLimits(_user, _liquidityPool, currencyAmount, trancheTokenAmount);
        } else {
            uint256 transferAmount = trancheTokenAmount - lpValues.maxMint;
            lpValues.maxDeposit = 0;
            lpValues.maxMint = 0;

            require(lPool.balanceOf(_user) >= transferAmount, "IM/insufficient-tranche-token-balance");
            require(lPool.transferFrom(_user, address(escrow), transferAmount), "IM/tranche-token-transfer-failed");
        }
        gateway.increaseRedeemOrder(
            lPool.poolId(), lPool.trancheId(), _user, currencyAddressToId[lPool.asset()], trancheTokenAmount
        );
    }

    function requestDeposit(uint256 _currencyAmount, address _user)
        public
        poolActive
        gatewayActive
        onlyLiquidityPoolWard
    {
        address _liquidityPool = msg.sender;
        LPValues storage lpValues = orderbook[_user][_liquidityPool];
        LiquidityPoolLike lPool = LiquidityPoolLike(_liquidityPool);
        ERC20Like currency = ERC20Like(lPool.asset());
        uint128 currencyAmount = _toUint128(_currencyAmount);

        require(_poolCurrencyCheck(lPool.poolId(), lPool.asset()), "IM/currency-not-supported");

        require(
            _liquidityPoolTokensCheck(lPool.poolId(), lPool.trancheId(), lPool.asset(), _user),
            "IM/tranche-tokens-not-supported"
        );

        if (currencyAmount == 0) {
            return;
        }
        if (lpValues.maxWithdraw >= currencyAmount) {
            uint128 userTrancheTokenPrice = calcRedeemTrancheTokenPrice(_user, _liquidityPool);
            uint128 trancheTokens = currencyAmount / userTrancheTokenPrice;
            _decreaseRedemptionLimits(_user, _liquidityPool, currencyAmount, trancheTokens);
        } else {
            uint128 transferAmount = currencyAmount - lpValues.maxWithdraw;
            lpValues.maxWithdraw = 0;
            lpValues.maxRedeem = 0;

            require(currency.balanceOf(_user) >= transferAmount, "IM/insufficient-balance");
            require(currency.transferFrom(_user, address(escrow), transferAmount), "IM/currency-transfer-failed");
        }
        gateway.increaseInvestOrder(
            lPool.poolId(), lPool.trancheId(), _user, currencyAddressToId[lPool.asset()], currencyAmount
        );
    }

    function collectInvest(uint64 _poolId, bytes16 _trancheId, address _user, address _currency)
        public
        onlyLiquidityPoolWard
    {
        LiquidityPoolLike lPool = LiquidityPoolLike(msg.sender);
        require(lPool.hasMember(_user), "IM/not-a-member");
        require(_poolCurrencyCheck(_poolId, _currency), "IM/currency-not-supported");
        gateway.collectInvest(_poolId, _trancheId, _user, currencyAddressToId[_currency]);
    }

    function collectRedeem(uint64 _poolId, bytes16 _trancheId, address _user, address _currency)
        public
        onlyLiquidityPoolWard
    {
        LiquidityPoolLike lPool = LiquidityPoolLike(msg.sender);
        require(lPool.hasMember(_user), "IM/not-a-member");
        require(_poolCurrencyCheck(_poolId, _currency), "IM/currency-not-supported");
        gateway.collectRedeem(_poolId, _trancheId, _user, currencyAddressToId[_currency]);
    }

    function transfer(address currencyAddress, bytes32 recipient, uint128 amount) public {
        uint128 currency = currencyAddressToId[currencyAddress];
        require(currency != 0, "IM/unknown-currency");

        ERC20Like erc20 = ERC20Like(currencyAddress);
        require(erc20.balanceOf(msg.sender) >= amount, "IM/insufficient-balance");
        require(erc20.transferFrom(msg.sender, address(escrow), amount), "IM/currency-transfer-failed");

        gateway.transfer(currency, msg.sender, recipient, amount);
    }

    function addCurrency(uint128 currency, address currencyAddress) public onlyGateway {
        require(currency > 0, "IM/invalid-currency-id");
        require(currencyIdToAddress[currency] == address(0), "IM/currency-id-in-use");
        require(currencyAddressToId[currencyAddress] == 0, "IM/currency-address-in-use");

        currencyIdToAddress[currency] = currencyAddress;
        currencyAddressToId[currencyAddress] = currency;

        EscrowLike(escrow).approve(currencyAddress, address(this), MAX_UINT256);
        emit CurrencyAdded(currency, currencyAddress);
    }

    function addPool(uint64 poolId) public onlyGateway {
        Pool storage pool = pools[poolId];
        require(pool.createdAt == 0, "IM/pool-already-added");
        pool.poolId = poolId;
        pool.createdAt = block.timestamp;
        pool.isActive = true;
        emit PoolAdded(poolId);
    }

    function allowPoolCurrency(uint64 poolId, uint128 currency) public onlyGateway {
        Pool storage pool = pools[poolId];
        require(pool.createdAt > 0, "IM/invalid-pool");

        address currencyAddress = currencyIdToAddress[currency];
        require(currencyAddress != address(0), "IM/unknown-currency");

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
        require(pool.createdAt > 0, "IM/invalid-pool");
        Tranche storage tranche = tranches[_poolId][_trancheId];
        require(tranche.createdAt == 0, "IM/tranche-already-exists");

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
        require(tranche.createdAt > 0, "IM/invalid-pool-or-tranche");
        for (uint256 i = 0; i < tranche.liquidityPools.length; i++) {
            address lPool = tranche.liquidityPools[i];
            require(lPool != address(0), "IM/invalid-liquidity-pool");
            LiquidityPoolLike(lPool).updateTokenPrice(_price);
        }
    }

    function updateMember(uint64 _poolId, bytes16 _trancheId, address _user, uint64 _validUntil) public onlyGateway {
        Tranche storage tranche = tranches[_poolId][_trancheId];
        require(tranche.createdAt > 0, "IM/invalid-pool-or-tranche");
        for (uint256 i = 0; i < tranche.liquidityPools.length; i++) {
            address lPool_ = tranche.liquidityPools[i];
            require(lPool_ != address(0), "IM/invalid-liquidity-pool");
            LiquidityPoolLike lPool = LiquidityPoolLike(lPool_);
            MemberlistLike memberlist = MemberlistLike(lPool.memberlist());
            memberlist.updateMember(_user, _validUntil);
        }
    }

    function handleExecutedCollectInvest(
        uint64 _poolId,
        bytes16 _trancheId,
        address _recepient,
        uint128 _currency,
        uint128 _currencyInvested,
        uint128 _tokensPayout
    ) public onlyGateway {
        require(_currencyInvested != 0, "IM/zero-invest");
        address currency = currencyIdToAddress[_currency];
        address lPool = liquidityPools[_poolId][_trancheId][currency];
        require(lPool != address(0), "IM/tranche-does-not-exist");

        LPValues storage values = orderbook[_recepient][lPool];
        values.maxDeposit = values.maxDeposit + _currencyInvested;
        values.maxMint = values.maxMint + _tokensPayout;

        LiquidityPoolLike(lPool).mint(address(escrow), _tokensPayout);
    }

    function handleExecutedCollectRedeem(
        uint64 _poolId,
        bytes16 _trancheId,
        address _recepient,
        uint128 _currency,
        uint128 _currencyPayout,
        uint128 _trancheTokensRedeemed
    ) public onlyGateway {
        require(_trancheTokensRedeemed != 0, "IM/zero-redeem");
        address currency = currencyIdToAddress[_currency];
        address lPool = liquidityPools[_poolId][_trancheId][currency];
        require(lPool != address(0), "IM/tranche-does-not-exist");

        LPValues storage values = orderbook[_recepient][lPool];
        values.maxWithdraw = values.maxWithdraw + _currencyPayout;
        values.maxRedeem = values.maxRedeem + _trancheTokensRedeemed;

        LiquidityPoolLike(lPool).burn(address(escrow), _trancheTokensRedeemed);
    }

    function handleExecutedDecreaseInvestOrder(
        uint64 _poolId,
        bytes16 _trancheId,
        address _user,
        uint128 _currency,
        uint128 _currencyPayout
    ) public onlyGateway {
        require(_currencyPayout != 0, "IM/zero-payout");
        address currency = currencyIdToAddress[_currency];
        LiquidityPoolLike lPool = LiquidityPoolLike(liquidityPools[_poolId][_trancheId][currency]);
        require(address(lPool) != address(0), "IM/tranche-does-not-exist");
        require(allowedPoolCurrencies[_poolId][currency], "IM/pool-currency-not-allowed");
        require(currency != address(0), "IM/unknown-currency");
        require(currency == lPool.asset(), "IM/not-tranche-currency");
        require(
            ERC20Like(currency).transferFrom(address(escrow), _user, _currencyPayout), "IM/currency-transfer-failed"
        );
    }

    function handleExecutedDecreaseRedeemOrder(
        uint64 _poolId,
        bytes16 _trancheId,
        address _user,
        uint128 _currency,
        uint128 _tokensPayout
    ) public onlyGateway {
        require(_tokensPayout != 0, "IM/zero-payout");
        address currency = currencyIdToAddress[_currency];
        LiquidityPoolLike lPool = LiquidityPoolLike(liquidityPools[_poolId][_trancheId][currency]);
        require(address(lPool) != address(0), "IM/tranche-does-not-exist");

        require(LiquidityPoolLike(lPool).hasMember(_user), "IM/not-a-member");
        require(lPool.transferFrom(address(escrow), _user, _tokensPayout), "IM/trancheTokens-transfer-failed");
    }

    function handleTransfer(uint128 currency, address recipient, uint128 amount) public onlyGateway {
        address currencyAddress = currencyIdToAddress[currency];
        require(currencyAddress != address(0), "IM/unknown-currency");

        EscrowLike(escrow).approve(currencyAddress, address(this), amount);
        require(
            ERC20Like(currencyAddress).transferFrom(address(escrow), recipient, amount), "IM/currency-transfer-failed"
        );
    }

    function maxDeposit(address _user, address _liquidityPool) public view returns (uint256 currencyAmount) {
        currencyAmount = uint256(orderbook[_user][_liquidityPool].maxDeposit);
    }

    function maxMint(address _user, address _liquidityPool) public view returns (uint256 trancheTokenAmount) {
        trancheTokenAmount = uint256(orderbook[_user][_liquidityPool].maxMint);
    }

    function maxWithdraw(address _user, address _liquidityPool) public view returns (uint256 currencyAmount) {
        currencyAmount = uint256(orderbook[_user][_liquidityPool].maxWithdraw);
    }

    function maxRedeem(address _user, address _liquidityPool) public view returns (uint256 trancheTokenAmount) {
        trancheTokenAmount = uint256(orderbook[_user][_liquidityPool].maxRedeem);
    }

    function processDeposit(address _user, uint256 _currencyAmount)
        public
        gatewayActive
        poolActive
        onlyLiquidityPoolWard
        returns (uint256)
    {
        address _liquidityPool = msg.sender;
        uint128 currencyAmount = _toUint128(_currencyAmount);
        LiquidityPoolLike lPool = LiquidityPoolLike(_liquidityPool);

        require((currencyAmount <= orderbook[_user][_liquidityPool].maxDeposit), "IM/amount-exceeds-deposit-limits");
        uint128 userTrancheTokenPriceLP = calcDepositTrancheTokenPrice(_user, _liquidityPool);
        require((userTrancheTokenPriceLP > 0), "LiquidityPool/amount-exceeds-deposit-limits");
        uint128 trancheTokenAmount = currencyAmount / userTrancheTokenPriceLP;

        _decreaseDepositLimits(_user, _liquidityPool, currencyAmount, trancheTokenAmount);
        require(lPool.hasMember(_user), "IM/trancheTokens-not-a-member");
        require(lPool.transferFrom(address(escrow), _user, trancheTokenAmount), "IM/trancheTokens-transfer-failed");

        emit DepositProcessed(_liquidityPool, _user, currencyAmount);
        return uint256(trancheTokenAmount);
    }

    function processMint(address _user, uint256 _trancheTokenAmount)
        public
        poolActive
        gatewayActive
        onlyLiquidityPoolWard
        returns (uint256)
    {
        address _liquidityPool = msg.sender;
        uint128 trancheTokenAmount = _toUint128(_trancheTokenAmount);
        LiquidityPoolLike lPool = LiquidityPoolLike(_liquidityPool);

        require((trancheTokenAmount <= orderbook[_user][_liquidityPool].maxMint), "IM/amount-exceeds-mint-limits");

        uint128 userTrancheTokenPriceLP = calcDepositTrancheTokenPrice(_user, _liquidityPool);
        require((userTrancheTokenPriceLP > 0), "LiquidityPool/amount-exceeds-mint-limits");
        uint128 currencyAmount = trancheTokenAmount * userTrancheTokenPriceLP;
        _decreaseDepositLimits(_user, _liquidityPool, currencyAmount, trancheTokenAmount);
        require(lPool.hasMember(_user), "IM/trancheTokens-not-a-member");
        require(lPool.transferFrom(address(escrow), _user, trancheTokenAmount), "IM/trancheTokens-transfer-failed");

        emit DepositProcessed(_liquidityPool, _user, currencyAmount);
        return uint256(currencyAmount);
    }

    function processRedeem(uint256 _trancheTokenAmount, address _receiver, address _user)
        public
        poolActive
        gatewayActive
        onlyLiquidityPoolWard
        returns (uint256)
    {
        address _liquidityPool = msg.sender;
        uint128 trancheTokenAmount = _toUint128(_trancheTokenAmount);
        LiquidityPoolLike lPool = LiquidityPoolLike(_liquidityPool);

        require((trancheTokenAmount <= orderbook[_user][_liquidityPool].maxRedeem), "IM/amount-exceeds-redeem-limits");
        uint128 userTrancheTokenPriceLP = calcRedeemTrancheTokenPrice(_user, _liquidityPool);
        require((userTrancheTokenPriceLP > 0), "LiquidityPool/amount-exceeds-redemption-limits");
        uint128 currencyAmount = trancheTokenAmount * userTrancheTokenPriceLP;

        _decreaseRedemptionLimits(_user, _liquidityPool, currencyAmount, trancheTokenAmount);
        require(
            ERC20Like(lPool.asset()).transferFrom(address(escrow), _receiver, currencyAmount),
            "IM/shares-transfer-failed"
        );

        emit RedemptionProcessed(_liquidityPool, _user, trancheTokenAmount);
        return uint256(currencyAmount);
    }

    function processWithdraw(uint256 _currencyAmount, address _receiver, address _user)
        public
        poolActive
        gatewayActive
        onlyLiquidityPoolWard
        returns (uint256)
    {
        address _liquidityPool = msg.sender;
        uint128 currencyAmount = _toUint128(_currencyAmount);
        LiquidityPoolLike lPool = LiquidityPoolLike(_liquidityPool);

        require((currencyAmount <= orderbook[_user][_liquidityPool].maxWithdraw), "IM/amount-exceeds-withdraw-limits");
        uint128 userTrancheTokenPriceLP = calcRedeemTrancheTokenPrice(_user, _liquidityPool);
        require((userTrancheTokenPriceLP > 0), "LiquidityPool/amount-exceeds-withdraw-limits");
        uint128 trancheTokenAmount = currencyAmount / userTrancheTokenPriceLP;

        _decreaseRedemptionLimits(_user, _liquidityPool, currencyAmount, trancheTokenAmount);
        require(
            ERC20Like(lPool.asset()).transferFrom(address(escrow), _receiver, currencyAmount),
            "IM/trancheTokens-transfer-failed"
        );
        return uint256(trancheTokenAmount);
    }

    function deployLiquidityPool(uint64 _poolId, bytes16 _trancheId, address _currency) public returns (address) {
        address liquidityPool = liquidityPools[_poolId][_trancheId][_currency];
        require(liquidityPool == address(0), "IM/liquidityPool-already-deployed");
        require(pools[_poolId].createdAt > 0, "IM/pool-does-not-exist");
        Tranche storage tranche = tranches[_poolId][_trancheId];
        require(tranche.createdAt != 0, "IM/tranche-does-not-exist");
        require(_poolCurrencyCheck(_poolId, _currency), "IM/currency-not-supported");
        uint128 currencyId = currencyAddressToId[_currency];

        address memberlist = memberlistFactory.newMemberlist(address(gateway), address(this));
        MemberlistLike(memberlist).updateMember(address(escrow), type(uint256).max);
        liquidityPool = liquidityPoolFactory.newLiquidityPool(
            _poolId,
            _trancheId,
            currencyId,
            _currency,
            address(this),
            address(gateway),
            memberlist,
            tranche.tokenName,
            tranche.tokenSymbol,
            tranche.decimals
        );
        liquidityPools[_poolId][_trancheId][_currency] = liquidityPool;
        liquidityPoolWards[liquidityPool] = 1;
        tranche.liquidityPools.push(liquidityPool);

        EscrowLike(escrow).approve(liquidityPool, address(this), MAX_UINT256);

        emit LiquidityPoolDeployed(_poolId, _trancheId, liquidityPool);
        return liquidityPool;
    }

    function calcDepositTrancheTokenPrice(address _user, address _liquidityPool)
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

    function calcRedeemTrancheTokenPrice(address _user, address _liquidityPool)
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
        require(currency != 0, "IM/unknown-currency");
        require(allowedPoolCurrencies[_poolId][_currencyAddress], "IM/pool-currency-not-allowed");
        return true;
    }

    function _liquidityPoolTokensCheck(uint64 _poolId, bytes16 _trancheId, address _currency, address _user)
        internal
        returns (bool)
    {
        LiquidityPoolLike lPool = LiquidityPoolLike(liquidityPools[_poolId][_trancheId][_currency]);
        require(address(lPool) != address(0), "IM/unknown-liquidity-pool");
        require(lPool.hasMember(_user), "IM/not-a-member");
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

    function _toUint128(uint256 _value) internal view returns (uint128 value) {
        if (_value > MAX_UINT128) {
            revert();
        } else {
            value = uint128(_value);
        }
    }
}
