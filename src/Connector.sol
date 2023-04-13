// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.18;
pragma abicoder v2;

import {RestrictedTokenFactoryLike, MemberlistFactoryLike} from "./token/factory.sol";
import {RestrictedTokenLike, ERC20Like} from "./token/restricted.sol";
import {MemberlistLike} from "./token/memberlist.sol";

interface GatewayLike {
    function transferTrancheTokensToCentrifuge(
        uint64 poolId,
        bytes16 trancheId,
        bytes32 destinationAddress,
        uint128 amount
    ) external;
    function transferTrancheTokensToEVM(
        uint64 poolId,
        bytes16 trancheId,
        uint256 destinationChainId,
        address destinationAddress,
        uint128 amount
    ) external;
    function transfer(uint128 currency, address sender, bytes32 recipient, uint128 amount) external;
    function increaseInvestOrder(uint64 poolId, bytes16 trancheId, uint128 amount) external;
    function decreaseInvestOrder(uint64 poolId, bytes16 trancheId, uint128 amount) external;
    function increaseRedeemOrder(uint64 poolId, bytes16 trancheId, uint128 amount) external;
    function decreaseRedeemOrder(uint64 poolId, bytes16 trancheId, uint128 amount) external;
    function collectRedeem(uint64 poolId, bytes16 trancheId, address caller) external;
    function collectForRedeem(uint64 poolId, bytes16 trancheId, address caller, bytes32 recipient) external;
    function collectInvest(uint64 poolId, bytes16 trancheId, address caller) external;
    function collectForInvest(uint64 poolId, bytes16 trancheId, address caller, bytes32 recipient) external;
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

enum CurrencyLevel {
    // Unknown currency
    None,
    // A currency has been added so we know the id -> address mapping
    Added,
    // A currency has been added AND allowed as a pool currency
    Allowed
}

struct Currency {
    //todo(nuno): name deviation here but it seems that's what we use for `Tranche`
    address token;
    CurrencyLevel level;
}

contract CentrifugeConnector {
    mapping(address => uint256) public wards;
    mapping(uint64 => Pool) public pools;
    mapping(uint64 => mapping(bytes16 => Tranche)) public tranches;
    mapping(uint128 => Currency) public currencies;

    GatewayLike public gateway;
    EscrowLike public escrow;

    RestrictedTokenFactoryLike public immutable tokenFactory;
    MemberlistFactoryLike public immutable memberlistFactory;

    // --- Events ---
    event Rely(address indexed user);
    event Deny(address indexed user);
    event File(bytes32 indexed what, address data);
    event CurrencyAdded(uint128 indexed currency, address indexed currencyAddress);
    event PoolAdded(uint256 indexed poolId);
    event PoolCurrencyAllowed(uint128 currency);
    event TrancheAdded(uint256 indexed poolId, bytes16 indexed trancheId);
    event TrancheDeployed(uint256 indexed poolId, bytes16 indexed trancheId, address indexed token);

    constructor(address escrow_, address tokenFactory_, address memberlistFactory_) {
        escrow = EscrowLike(escrow_);
        tokenFactory = RestrictedTokenFactoryLike(tokenFactory_);
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
    function transfer(uint128 currency, bytes32 recipient, uint128 amount) public {
        // todo(nuno)
        // 1. Ensure currency exists

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

        gateway.transferTrancheTokensToCentrifuge(poolId, trancheId, destinationAddress, amount);
    }

    function transferTrancheTokensToEVM(
        uint64 poolId,
        bytes16 trancheId,
        uint256 destinationChainId,
        address destinationAddress,
        uint128 amount
    ) public {
        RestrictedTokenLike token = RestrictedTokenLike(tranches[poolId][trancheId].token);
        require(address(token) != address(0), "CentrifugeConnector/unknown-token");

        require(token.balanceOf(msg.sender) >= amount, "CentrifugeConnector/insufficient-balance");
        token.burn(msg.sender, amount);

        gateway.transferTrancheTokensToEVM(poolId, trancheId, destinationChainId, destinationAddress, amount);
    }

    function increaseInvestOrder(uint64 poolId, bytes16 trancheId, uint128 amount) public {
        Pool storage pool = pools[poolId];
        require(pool.createdAt > 0, "CentrifugeConnector/invalid-pool");

        RestrictedTokenLike token = RestrictedTokenLike(tranches[poolId][trancheId].token);
        require(address(token) != address(0), "CentrifugeConnector/unknown-token");
        require(token.hasMember(msg.sender), "CentrifugeConnector/not-a-member");

        require(
            ERC20Like(pool.currency).transferFrom(msg.sender, address(escrow), amount),
            "Centrifuge/Connector/currency-transfer-failed"
        );

        gateway.increaseInvestOrder(poolId, trancheId, amount);
    }

    function decreaseInvestOrder(uint64 poolId, bytes16 trancheId, uint128 amount) public {
        Pool storage pool = pools[poolId];
        require(pool.createdAt > 0, "CentrifugeConnector/invalid-pool");

        RestrictedTokenLike token = RestrictedTokenLike(tranches[poolId][trancheId].token);
        require(address(token) != address(0), "CentrifugeConnector/unknown-token");
        require(token.hasMember(msg.sender), "CentrifugeConnector/not-a-member");

        gateway.decreaseInvestOrder(poolId, trancheId, amount);
    }

    function increaseRedeemOrder(uint64 poolId, bytes16 trancheId, uint128 amount) public {
        // TODO(nuno)

        gateway.increaseRedeemOrder(poolId, trancheId, amount);
    }

    function decreaseRedeemOrder(uint64 poolId, bytes16 trancheId, uint128 amount) public {
        // TODO(nuno)

        gateway.decreaseRedeemOrder(poolId, trancheId, amount);
    }

    function collectRedeem(uint64 poolId, bytes16 trancheId) public {
        // TODO(nuno)

        gateway.collectRedeem(poolId, trancheId, address(msg.sender));
    }

    function collectForRedeem(uint64 poolId, bytes16 trancheId, bytes32 recipient) public {
        // TODO(nuno)

        gateway.collectForRedeem(poolId, trancheId, address(msg.sender), recipient);
    }

    function collectInvest(uint64 poolId, bytes16 trancheId) public {
        // TODO(nuno)

        gateway.collectInvest(poolId, trancheId, address(msg.sender));
    }

    function collectForInvest(uint64 poolId, bytes16 trancheId, bytes32 recipient) public {
        // TODO(nuno)

        gateway.collectForInvest(poolId, trancheId, address(msg.sender), recipient);
    }

    // --- Incoming message handling ---
    function addCurrency(uint128 currency, address currencyAddress) public onlyGateway {
        require(address(ERC20Like(currencyAddress)) != address(0), "CentrifugeConnector/unknown-token");

        Currency storage entry = currencies[currency];
        require(entry.level == CurrencyLevel.None, "CentrifugeConnector/currency-already-added");

        entry.token = currencyAddress;
        entry.level = CurrencyLevel.Added;
        emit CurrencyAdded(currency, currencyAddress);
    }

    function addPool(uint64 poolId) public onlyGateway {
        Pool storage pool = pools[poolId];
        pool.poolId = poolId;
        pool.createdAt = block.timestamp;
        emit PoolAdded(poolId);
    }

    function allowPoolCurrency(uint128 currency) public onlyGateway {
        Currency storage entry = currencies[currency];
        require(entry.level != CurrencyLevel.Allowed, "CentrifugeConnector/currency-already-allowed");

        entry.level = CurrencyLevel.Allowed;
        emit PoolCurrencyAllowed(currency);
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

        address token = tokenFactory.newRestrictedToken(tranche.tokenName, tranche.tokenSymbol, tranche.decimals);
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

    function handleTransferTrancheTokens(
        uint64 poolId,
        bytes16 trancheId,
        uint256 destinationChainId,
        address destinationAddress,
        uint128 amount
    ) public onlyGateway {
        require(destinationChainId == block.chainid, "CentrifugeConnector/invalid-chain-id");
        RestrictedTokenLike token = RestrictedTokenLike(tranches[poolId][trancheId].token);
        require(address(token) != address(0), "CentrifugeConnector/unknown-token");

        require(token.hasMember(destinationAddress), "CentrifugeConnector/not-a-member");
        token.mint(destinationAddress, amount);
    }
}
