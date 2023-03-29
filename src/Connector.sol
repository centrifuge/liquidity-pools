// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.18;
pragma abicoder v2;

import {RestrictedTokenFactoryLike, MemberlistFactoryLike} from "./token/factory.sol";
import {RestrictedTokenLike, ERC20Like} from "./token/restricted.sol";
import {MemberlistLike} from "./token/memberlist.sol";
// TODO: remove dependency on Messages.sol
import {ConnectorMessages} from "src/Messages.sol";

interface GatewayLike {
    function transferToCentrifuge(
        uint64 poolId,
        bytes16 trancheId,
        bytes32 destinationAddress,
        uint128 amount
    ) external;
    function transferToEVM(
        uint64 poolId,
        bytes16 trancheId,
        uint256 destinationChainId,
        address destinationAddress,
        uint128 amount
    ) external;
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
}

contract CentrifugeConnector {
    mapping(address => uint256) public wards;
    mapping(uint64 => Pool) public pools;
    mapping(uint64 => mapping(bytes16 => Tranche)) public tranches;

    GatewayLike public gateway;
    EscrowLike public escrow;

    RestrictedTokenFactoryLike public immutable tokenFactory;
    MemberlistFactoryLike public immutable memberlistFactory;

    // --- Events ---
    event Rely(address indexed user);
    event Deny(address indexed user);
    event File(bytes32 indexed what, address data);
    event PoolAdded(uint256 indexed poolId);
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
    function transferToCentrifuge(uint64 poolId, bytes16 trancheId, bytes32 destinationAddress, uint128 amount)
        public
    {
        RestrictedTokenLike token = RestrictedTokenLike(tranches[poolId][trancheId].token);
        require(address(token) != address(0), "CentrifugeConnector/unknown-token");

        require(token.balanceOf(msg.sender) >= amount, "CentrifugeConnector/insufficient-balance");
        token.burn(msg.sender, amount);

        gateway.transferToCentrifuge(poolId, trancheId, destinationAddress, amount);
    }

    function transferToEVM(uint64 poolId, bytes16 trancheId,uint256 destinationChainId, address destinationAddress, uint128 amount)
        public
    {
        RestrictedTokenLike token = RestrictedTokenLike(tranches[poolId][trancheId].token);
        require(address(token) != address(0), "CentrifugeConnector/unknown-token");

        require(token.balanceOf(msg.sender) >= amount, "CentrifugeConnector/insufficient-balance");
        token.burn(msg.sender, amount);

        gateway.transferToEVM(poolId, trancheId, destinationChainId, destinationAddress, amount);
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

        // TODO: send message to the gateway. Depends on https://github.com/centrifuge/connectors/pull/52
    }

    // --- Incoming message handling ---
    function addPool(uint64 poolId) public onlyGateway {
        Pool storage pool = pools[poolId];
        pool.poolId = poolId;
        pool.createdAt = block.timestamp;
        emit PoolAdded(poolId);
    }

    function addTranche(
        uint64 poolId,
        bytes16 trancheId,
        string memory tokenName,
        string memory tokenSymbol,
        uint128 price
    ) public onlyGateway {
        Pool storage pool = pools[poolId];
        require(pool.createdAt > 0, "CentrifugeConnector/invalid-pool");

        Tranche storage tranche = tranches[poolId][trancheId];
        tranche.latestPrice = price;
        tranche.lastPriceUpdate = block.timestamp;
        tranche.tokenName = tokenName;
        tranche.tokenSymbol = tokenSymbol;

        emit TrancheAdded(poolId, trancheId);
    }

    function deployTranche(uint64 poolId, bytes16 trancheId) public {
        Tranche storage tranche = tranches[poolId][trancheId];
        require(tranche.lastPriceUpdate > 0, "CentrifugeConnector/invalid-pool-or-tranche");

        // TODO: use actual decimals
        uint8 decimals = 18;
        address token = tokenFactory.newRestrictedToken(tranche.tokenName, tranche.tokenSymbol, decimals);
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

    function handleTransfer(uint64 poolId, bytes16 trancheId, uint256 destinationChainId, address destinationAddress, uint128 amount)
        public
        onlyGateway
    {
        
        require(destinationChainId == block.chainid, "CentrifugeConnector/invalid-chain-id");
        RestrictedTokenLike token = RestrictedTokenLike(tranches[poolId][trancheId].token);
        require(address(token) != address(0), "CentrifugeConnector/unknown-token");

        require(token.hasMember(destinationAddress), "CentrifugeConnector/not-a-member");
        token.mint(destinationAddress, amount);
    }
}
