// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.18;
pragma abicoder v2;

import {TrancheTokenFactoryLike, MemberlistFactoryLike} from "./token/factory.sol";
import {RestrictedTokenLike, ERC20Like} from "./token/restricted.sol";
import {MemberlistLike} from "./token/memberlist.sol";

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
}

interface EscrowLike {
    function approve(address token, address spender, uint256 value) external;
}

struct Pool {
    uint64 poolId;
    uint256 createdAt;
    address currency;
}

struct Tranche {
    address token;
    uint128 latestPrice; // Fixed point integer with 27 decimals
    uint256 lastPriceUpdate;
    // TODO: the token name & symbol need to be stored because of the separation between adding and deploying tranches.
    // This leads to duplicate storage (also in the ERC20 contract), ideally we should refactor this somehow
    string tokenName;
    string tokenSymbol;
    uint8 decimals;
}

contract CentrifugeConnector {
    mapping(address => uint256) public wards;
    mapping(uint64 => Pool) public pools;
    mapping(uint64 => mapping(bytes16 => Tranche)) public tranches;

    mapping(uint128 => address) public currencyIdToAddress;
    // The reverse mapping of `currencyIdToAddress`
    mapping(address => uint128) public currencyAddressToId;

    mapping(uint64 => mapping(address => bool)) public allowedPoolCurrencies;

    GatewayLike public gateway;
    EscrowLike public immutable escrow;

    TrancheTokenFactoryLike public immutable tokenFactory;
    MemberlistFactoryLike public immutable memberlistFactory;

    // --- Events ---
    event Rely(address indexed user);
    event Deny(address indexed user);
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

    modifier auth() {
        require(wards[msg.sender] == 1, "CentrifugeConnector/not-authorized");
        _;
    }

    modifier onlyGateway() {
        require(msg.sender == address(gateway), "CentrifugeConnector/not-the-gateway");
        _;
    }

    // --- Administration ---
    function rely(address user) external auth {
        wards[user] = 1;
        emit Rely(user);
    }

    function deny(address user) external auth {
        wards[user] = 0;
        emit Deny(user);
    }

    function file(bytes32 what, address data) external auth {
        if (what == "gateway") gateway = GatewayLike(data);
        else revert("CentrifugeConnector/file-unrecognized-param");
        emit File(what, data);
    }

    // --- Outgoing message handling ---
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
        RestrictedTokenLike token = RestrictedTokenLike(tranches[poolId][trancheId].token);
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
        RestrictedTokenLike token = RestrictedTokenLike(tranches[poolId][trancheId].token);
        require(address(token) != address(0), "CentrifugeConnector/unknown-token");

        require(token.balanceOf(msg.sender) >= amount, "CentrifugeConnector/insufficient-balance");
        token.burn(msg.sender, amount);

        gateway.transferTrancheTokensToEVM(
            poolId, trancheId, msg.sender, destinationChainId, destinationAddress, amount
        );
    }

    function increaseInvestOrder(uint64 poolId, bytes16 trancheId, address currencyAddress, uint128 amount) public {
        RestrictedTokenLike token = RestrictedTokenLike(tranches[poolId][trancheId].token);
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
        RestrictedTokenLike token = RestrictedTokenLike(tranches[poolId][trancheId].token);
        require(address(token) != address(0), "CentrifugeConnector/unknown-tranche-token");
        require(token.hasMember(msg.sender), "CentrifugeConnector/not-a-member");

        uint128 currency = currencyAddressToId[currencyAddress];
        require(currency != 0, "CentrifugeConnector/unknown-currency");
        require(allowedPoolCurrencies[poolId][currencyAddress], "CentrifugeConnector/pool-currency-not-allowed");

        gateway.increaseRedeemOrder(poolId, trancheId, msg.sender, currency, amount);
    }

    function decreaseRedeemOrder(uint64 poolId, bytes16 trancheId, address currencyAddress, uint128 amount) public {
        RestrictedTokenLike token = RestrictedTokenLike(tranches[poolId][trancheId].token);
        require(address(token) != address(0), "CentrifugeConnector/unknown-tranche-token");
        require(token.hasMember(msg.sender), "CentrifugeConnector/not-a-member");

        uint128 currency = currencyAddressToId[currencyAddress];
        require(currency != 0, "CentrifugeConnector/unknown-currency");
        require(allowedPoolCurrencies[poolId][currencyAddress], "CentrifugeConnector/pool-currency-not-allowed");

        gateway.decreaseRedeemOrder(poolId, trancheId, msg.sender, currency, amount);
    }

    function collectInvest(uint64 poolId, bytes16 trancheId) public {
        RestrictedTokenLike token = RestrictedTokenLike(tranches[poolId][trancheId].token);
        require(address(token) != address(0), "CentrifugeConnector/unknown-tranche-token");
        require(token.hasMember(msg.sender), "CentrifugeConnector/not-a-member");

        gateway.collectInvest(poolId, trancheId, address(msg.sender));
    }

    function collectRedeem(uint64 poolId, bytes16 trancheId) public {
        RestrictedTokenLike token = RestrictedTokenLike(tranches[poolId][trancheId].token);
        require(address(token) != address(0), "CentrifugeConnector/unknown-tranche-token");
        require(token.hasMember(msg.sender), "CentrifugeConnector/not-a-member");

        gateway.collectRedeem(poolId, trancheId, address(msg.sender));
    }

    // --- Incoming message handling ---
    function addCurrency(uint128 currency, address currencyAddress) public onlyGateway {
        require(currencyIdToAddress[currency] == address(0), "CentrifugeConnector/currency-already-added");
        require(currencyAddressToId[currencyAddress] == 0, "CentrifugeConnector/currency-already-added");

        currencyIdToAddress[currency] = currencyAddress;
        currencyAddressToId[currencyAddress] = currency;
        emit CurrencyAdded(currency, currencyAddress);
    }

    function addPool(uint64 poolId) public onlyGateway {
        Pool storage pool = pools[poolId];
        require(pool.createdAt == 0, "CentrifugeConnector/pool-already-added");
        pool.poolId = poolId;
        pool.createdAt = block.timestamp;
        emit PoolAdded(poolId);
    }

    function allowPoolCurrency(uint128 currency, uint64 poolId) public onlyGateway {
        Pool storage pool = pools[poolId];
        require(pool.createdAt > 0, "CentrifugeConnector/invalid-pool");

        address currencyAddress = currencyIdToAddress[currency];
        require(currencyAddress != address(0), "CentrifugeConnector/unknown-currency");

        allowedPoolCurrencies[poolId][currencyAddress] = true;
        emit PoolCurrencyAllowed(currency, poolId);
    }

    function addTranche(
        uint64 poolId,
        bytes16 trancheId,
        string memory tokenName,
        string memory tokenSymbol,
        uint8 decimals,
        uint128 price
    ) public onlyGateway {
        Pool storage pool = pools[poolId];
        require(pool.createdAt > 0, "CentrifugeConnector/invalid-pool");

        Tranche storage tranche = tranches[poolId][trancheId];
        require(tranche.lastPriceUpdate == 0, "CentrifugeConnector/tranche-already-added");
        tranche.latestPrice = price;
        tranche.lastPriceUpdate = block.timestamp;
        tranche.tokenName = tokenName;
        tranche.tokenSymbol = tokenSymbol;
        tranche.decimals = decimals;

        emit TrancheAdded(poolId, trancheId);
    }

    function deployTranche(uint64 poolId, bytes16 trancheId) public {
        Tranche storage tranche = tranches[poolId][trancheId];
        require(tranche.lastPriceUpdate > 0, "CentrifugeConnector/invalid-pool-or-tranche");
        require(tranche.token == address(0), "CentrifugeConnector/tranche-already-deployed");

        address token =
            tokenFactory.newTrancheToken(poolId, trancheId, tranche.tokenName, tranche.tokenSymbol, tranche.decimals);
        tranche.token = token;

        address memberlist = memberlistFactory.newMemberlist();
        RestrictedTokenLike(token).file("memberlist", memberlist);
        MemberlistLike(memberlist).updateMember(address(this), type(uint256).max); // required to be able to receive tokens in case of withdrawals
        emit TrancheDeployed(poolId, trancheId, token);
    }

    function updateTokenPrice(uint64 poolId, bytes16 trancheId, uint128 price) public onlyGateway {
        Tranche storage tranche = tranches[poolId][trancheId];
        require(tranche.lastPriceUpdate > 0, "CentrifugeConnector/invalid-pool-or-tranche");
        tranche.latestPrice = price;
        tranche.lastPriceUpdate = block.timestamp;
    }

    function updateMember(uint64 poolId, bytes16 trancheId, address user, uint64 validUntil) public onlyGateway {
        Tranche storage tranche = tranches[poolId][trancheId];
        require(tranche.lastPriceUpdate > 0, "CentrifugeConnector/invalid-pool-or-tranche");
        RestrictedTokenLike token = RestrictedTokenLike(tranche.token);
        MemberlistLike memberlist = MemberlistLike(token.memberlist());
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
        RestrictedTokenLike token = RestrictedTokenLike(tranches[poolId][trancheId].token);
        require(address(token) != address(0), "CentrifugeConnector/unknown-token");

        require(token.hasMember(destinationAddress), "CentrifugeConnector/not-a-member");
        token.mint(destinationAddress, amount);
    }
}
