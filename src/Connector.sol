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

interface TrancheLike {
    function updateTokenPrice(uint128 _tokenPrice) external;
    function asset() external returns (address);
}

interface EscrowLike {
    function approve(address token, address spender, uint256 value) external;
}

struct Pool {
    uint64 poolId;
    uint256 createdAt;
    bool isActive;
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

    modifier poolActive(uint64 poolId) {
        require(pools[poolId].isActive, "CentrifugeConnector/pool-deactivated");
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
    function deposit(address _tranche, address _receiver, uint256 _assets) public poolActive(_poolId) connectorsActive auth returns (uint256) {
        require((_assets <= orderbook[_receiver][_tranche].maxDeposit), "CentrifugeConnector/amount-exceeds-deposit-limits");
        uint256 sharePrice = calcUserSharePrice( _receiver, _tranche);
        require((sharePrice > 0), "Tranche4626/amount-exceeds-deposit-limits");
        uint256 sharesToTransfer = _assets / sharePrice;
        decreaseDepositLimits(_receiver, _tranche, _assets, sharesToTransfer); // decrease the possible deposit limits
        require(ERC20Like(_tranche).transferFrom(address(escrow), _receiver, sharesToTransfer), "CentrifugeConnector/shares-transfer-failed");
        return sharesToTransfer;
    }

    function mint(address _tranche, address _receiver, uint256 _shares) public poolActive(_poolId) connectorsActive auth returns (uint256) {
        require((_shares <= orderbook[_receiver][_tranche].maxMint), "CentrifugeConnector/amount-exceeds-mint-limits");
        uint256 sharePrice = calcUserSharePrice( _receiver, _tranche);
        require((sharePrice > 0), "Tranche4626/amount-exceeds-deposit-limits");
        uint256 requiredDeposit = _shares * sharePrice;
        decreaseDepositLimits(_receiver, _tranche, requiredDeposit, _shares); // decrease the possible deposit limits
        require(ERC20Like(_tranche).transferFrom(address(escrow), _receiver, _shares), "CentrifugeConnector/shares-transfer-failed");
        return requiredDeposit;
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

    function increaseInvestOrder(uint64 poolId, bytes16 trancheId, address currencyAddress, uint128 amount) public {
        RestrictedTokenLike token = RestrictedTokenLike(tranches[poolId][trancheId]);
        require(address(token) != address(0), "CentrifugeConnector/unknown-tranche-token");
        require(token.hasMember(msg.sender), "CentrifugeConnector/not-a-member");

        uint128 currency = currencyAddressToId[currencyAddress];
        require(currency != 0, "CentrifugeConnector/unknown-currency");
        require(allowedPoolCurrencies[poolId][currencyAddress], "CentrifugeConnector/pool-currency-not-allowed");

        require(
            ERC20Like(currencyAddress).transferFrom(msg.sender, address(escrow), amount),
            "Centrifuge/Connector/currency-transfer-failed"
        );

        gateway.increaseInvestOrder(poolId, trancheId, msg.sender, currency, amount);
    }

    function decreaseInvestOrder(uint64 poolId, bytes16 trancheId, address currencyAddress, uint128 amount) public {
        RestrictedTokenLike token = RestrictedTokenLike(tranches[poolId][trancheId].token);
        require(address(token) != address(0), "CentrifugeConnector/unknown-tranche-token");
        require(token.hasMember(msg.sender), "CentrifugeConnector/not-a-member");

        uint128 currency = currencyAddressToId[currencyAddress];
        require(currency != 0, "CentrifugeConnector/unknown-currency");
        require(allowedPoolCurrencies[poolId][currencyAddress], "CentrifugeConnector/pool-currency-not-allowed");

        gateway.decreaseInvestOrder(poolId, trancheId, msg.sender, currency, amount);
    }

    function increaseRedeemOrder(uint64 poolId, bytes16 trancheId, address currencyAddress, uint128 amount) public {
        RestrictedTokenLike token = RestrictedTokenLike(tranches[poolId][trancheId]);
        require(address(token) != address(0), "CentrifugeConnector/unknown-tranche-token");
        require(token.hasMember(msg.sender), "CentrifugeConnector/not-a-member");

        uint128 currency = currencyAddressToId[currencyAddress];
        require(currency != 0, "CentrifugeConnector/unknown-currency");
        require(allowedPoolCurrencies[poolId][currencyAddress], "CentrifugeConnector/pool-currency-not-allowed");

        gateway.increaseRedeemOrder(poolId, trancheId, msg.sender, currency, amount);
    }

    function decreaseRedeemOrder(uint64 poolId, bytes16 trancheId, address currencyAddress, uint128 amount) public {
        RestrictedTokenLike token = RestrictedTokenLike(tranches[poolId][trancheId]);
        require(address(token) != address(0), "CentrifugeConnector/unknown-tranche-token");
        require(token.hasMember(msg.sender), "CentrifugeConnector/not-a-member");

        uint128 currency = currencyAddressToId[currencyAddress];
        require(currency != 0, "CentrifugeConnector/unknown-currency");
        require(allowedPoolCurrencies[poolId][currencyAddress], "CentrifugeConnector/pool-currency-not-allowed");

        gateway.decreaseRedeemOrder(poolId, trancheId, msg.sender, currency, amount);
    }

    function collectInvest(uint64 poolId, bytes16 trancheId) public {
        RestrictedTokenLike token = RestrictedTokenLike(tranches[poolId][trancheId]);
        require(address(token) != address(0), "CentrifugeConnector/unknown-tranche-token");
        require(token.hasMember(msg.sender), "CentrifugeConnector/not-a-member");

        gateway.collectInvest(poolId, trancheId, address(msg.sender));
    }

    function collectRedeem(uint64 poolId, bytes16 trancheId) public {
        RestrictedTokenLike token = RestrictedTokenLike(tranches[poolId][trancheId]);
        require(address(token) != address(0), "CentrifugeConnector/unknown-tranche-token");
        require(token.hasMember(msg.sender), "CentrifugeConnector/not-a-member");

        gateway.collectRedeem(poolId, trancheId, address(msg.sender));
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

        address token = tranches[_poolId][_trancheId];
        require(token == address(0), "CentrifugeConnector/tranche-already-added");
        address asset = address(0x6B175474E89094C44Da98b954EedeAC495271d0F); // TODO FIX : provide tranche currency / assets : default DAI?
        token = deployTranche(poolId, trancheId, asset, tokenName, tokenSymbol, decimals);
        
        TrancheLike(token).updateTokenPrice(_price);

        emit TrancheAdded(poolId, trancheId);
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

    function handleDecreaseInvestOrder(uint64 _poolId, bytes16 _trancheId, address _recipient, uint128 _currency, uint128 _currencyPayout, uint128 _remainingInvestOrder) public onlyGateway {
        require(_currencyPayout != 0, "CentrifugeConnector/zero-payout");
        address currencyAddress = currencyIdToAddress[_currency];
        address tranche = tranches[_poolId][_trancheId];

        require(allowedPoolCurrencies[_poolId][currencyAddress], "CentrifugeConnector/pool-currency-not-allowed");
        require(currencyAddress != address(0), "CentrifugeConnector/unknown-currency");
        require(currencyAddress == TrancheLike(tranche).asset(), "CentrifugeConnector/not-tranche-currency");

        // TODO: escrow should give max approval on deployment
        EscrowLike(escrow).approve(currencyAddress, address(this), _currencyPayout);
   
        require(
            ERC20Like(currencyAddress).transferFrom(address(escrow), _recipient, _currencyPayout),
            "CentrifugeConnector/currency-transfer-failed"
        );
        orderbook[_recipient][tranche].openInvest = _remainingInvestOrder;
    }

    //TODO: currency not really required here
    function handleDecreaseRedeemOrder(uint64 _poolId, bytes16 _trancheId, address _recipient, uint128 _currency, uint128 _trancheTokensPayout, uint128 _remainingRedeemOrder) public onlyGateway {
        require(_trancheTokensPayout != 0, "CentrifugeConnector/zero-payout");
        address tranche = tranches[poolId][trancheId];

        require(RestrictedTokenLike(tranche).hasMember(_recipient), "CentrifugeConnector/not-a-member");
        // TODO: escrow should give max approval on deployment
        EscrowLike(escrow).approve(tranche, address(this), _trancheTokensPayout);
        require(
            ERC20Like(tranche).transferFrom(address(escrow), _recipient, _trancheTokensPayout),
            "CentrifugeConnector/trancheTokens-transfer-failed"
        );
        orderbook[_recipient][tranche].openRedeem = _remainingRedeemOrder;
    }

    function handleCollectInvest(uint64 poolId, bytes16 trancheId, address destinationAddress, uint128 currency, uint128 currencyInvested, uint128 tokensPayout, uint128 remainingInvestOrder) public onlyGateway {};
    function handleCollectRedeem(uint64 poolId, bytes16 trancheId, address destinationAddress, uint128 currency, uint128 currencyPayout, uint128 tokensRedeemed, uint128 remainingRedeemOrder) public onlyGateway {};


    // ------ internal helper functions 

    //TODO: rounding 
    function decreaseDepositLimits(address _user, address _tranche, uint256 _assets, uint256 _shares) internal {
        UserTrancheValues values = orderbook[_user][_tranche];
        if (values.maxDeposit < _assets) {
            values.maxDeposit = 0;
        } else {
             values.maxDeposit = values.maxDeposit - _assets;
        }
        if (values.maxMint < _shares) {
            values.maxMint = 0;
        } else {
             values.maxMint = values.maxMint - _shares;
        }
    }

    // function decreaseRedemptionsLimit(uint256 _assets, uint256 _shares) public auth {}


    // TODO: add decimals to constructor of restricted token
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
    function calcUserSharePrice(address _user, address _tranche) public view returns (uint256 sharePrice) {
        UserTrancheValues values = orderbook[_user][_tranche];
        if(values.maxMint == 0) {
            return 0;
        }
        sharePrice = values.maxDeposit / values.maxMint;
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
