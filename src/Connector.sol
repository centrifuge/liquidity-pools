// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.7.6;
pragma abicoder v2;

import { RestrictedTokenFactoryLike, MemberlistFactoryLike } from "./token/factory.sol";
import { RestrictedTokenLike } from "./token/restricted.sol";
import { MemberlistLike } from "./token/memberlist.sol";

interface RouterLike {
    function sendMessage(uint64 poolId, bytes16 trancheId, uint256 amount, address user) external;
}

contract CentrifugeConnector {

    RouterLike public router;
    RestrictedTokenFactoryLike public immutable tokenFactory;
    MemberlistFactoryLike public immutable memberlistFactory;

    enum Domain { EVM, Parachain }

    // --- Storage ---
    struct Pool {
        uint64 poolId;
        uint256 createdAt;
    }

    struct Tranche {
        address token;
        uint128 latestPrice; // [ray]
        uint256 lastPriceUpdate;
        // TODO: the token name & symbol need to be stored because of the separation between adding and deploying tranches.
        // This leads to duplicate storage (also in the ERC20 contract), ideally we should refactor this somehow
        string tokenName;
        string tokenSymbol;
    }

    mapping(uint64 => Pool) public pools;
    mapping(uint64 => mapping(bytes16 => Tranche)) public tranches;
    mapping(address => uint256) public wards;
    mapping(bytes32 => uint32) public domainsEVM;
    mapping(bytes32 => uint32) public domainsParachain;

    // --- Events ---
    event Rely(address indexed user);
    event Deny(address indexed user);
    event File(bytes32 indexed what, address data);
    event File(bytes32 indexed what, string data, uint32 data2);
    event PoolAdded(uint256 indexed poolId);
    event TrancheAdded(uint256 indexed poolId, bytes16 indexed trancheId);
    event TrancheDeployed(uint256 indexed poolId, bytes16 indexed trancheId, address indexed token);

    constructor(address tokenFactory_, address memberlistFactory_) {
        tokenFactory = RestrictedTokenFactoryLike(tokenFactory_);
        memberlistFactory = MemberlistFactoryLike(memberlistFactory_);
        wards[msg.sender] = 1;
        file("domainEVM", "centrifuge", 3000);
        emit Rely(msg.sender);
    }
    
    modifier auth {
        require(wards[msg.sender] == 1, "CentrifugeConnector/not-authorized");
        _;
    }

    modifier onlyRouter() {
        require(msg.sender == address(router), "CentrifugeConnector/not-the-router");
        _;
    }

    // --- Administration ---
    function rely(address usr) external auth {
        wards[usr] = 1;
        emit Rely(usr);
    }

    function deny(address usr) external auth {
        wards[usr] = 0;
        emit Deny(usr);
    }

    function file(bytes32 what, address data) external auth {
        if (what == "router") router = RouterLike(data);
        else revert("CentrifugeConnector/file-unrecognized-param");
        emit File(what, data);
    }

    function file(bytes32 name, string memory domainName, uint32 domainId) public auth  {
        if(name == "domainEVM") {
           domainsEVM[keccak256(bytes(domainName))] = domainId;
           emit File(name, domainName, domainId);
        } else if(name == "domainParachain") {
           domainsParachain[keccak256(bytes(domainName))] = domainId;
           emit File(name, domainName, domainId);
        } else { revert ("unknown name");}
    }

    // --- Internal ---
    function getDomain(Domain domain, string memory domainName) internal view returns (uint32) {
        if (domain == Domain.EVM) {
            return domainsEVM[keccak256(bytes(domainName))];
        } else if (domain == Domain.Parachain) {
            return domainsParachain[keccak256(bytes(domainName))];
        } else {
            revert("CentrifugeConnector/invalid-domain");
        }
    }

    function addPool(uint64 poolId) public onlyRouter {
        Pool storage pool = pools[poolId];
        pool.poolId = poolId;
        pool.createdAt = block.timestamp;
        emit PoolAdded(poolId);
    }

    function addTranche(uint64 poolId, bytes16 trancheId, string memory tokenName, string memory tokenSymbol, uint128 price)
        public
        onlyRouter
    {
        Pool storage pool = pools[poolId];
        require(pool.createdAt > 0, "CentrifugeConnector/invalid-pool");

        Tranche storage tranche = tranches[poolId][trancheId];
        tranche.latestPrice = price;
        tranche.tokenName = tokenName;
        tranche.tokenSymbol = tokenSymbol;

        emit TrancheAdded(poolId, trancheId);
    }

    function deployTranche(uint64 poolId, bytes16 trancheId) public {
        Pool storage pool = pools[poolId];
        require(pool.createdAt > 0, "CentrifugeConnector/invalid-pool");

        Tranche storage tranche = tranches[poolId][trancheId];
        address token = tokenFactory.newRestrictedToken(tranche.tokenName, tranche.tokenSymbol);
        tranche.token = token;

        address memberlist = memberlistFactory.newMemberlist();
        RestrictedTokenLike(token).depend("memberlist", memberlist);
        MemberlistLike(memberlist).updateMember(address(this), uint(-1)); // required to be able to receive tokens in case of withdrawals   
        emit TrancheDeployed(poolId, trancheId, token);
    }

    function updateTokenPrice(
        uint64 poolId,
        bytes16 trancheId,
        uint128 price
    ) public onlyRouter {
        Tranche storage tranche = tranches[poolId][trancheId];
        require(tranche.latestPrice > 0, "CentrifugeConnector/invalid-pool-or-tranche");
        tranche.latestPrice = price;
        tranche.lastPriceUpdate = block.timestamp;
    }

    function updateMember(
        uint64 poolId,
        bytes16 trancheId,
        address user,
        uint64 validUntil
    ) public onlyRouter {
        Tranche storage tranche = tranches[poolId][trancheId];
        require(tranche.latestPrice > 0, "CentrifugeConnector/invalid-pool-or-tranche");
        RestrictedTokenLike token = RestrictedTokenLike(tranche.token);
        MemberlistLike memberlist = MemberlistLike(token.memberlist());
        memberlist.updateMember(user, validUntil);
    }

    function handleTransfer(
        uint64 poolId,
        bytes16 trancheId,
        address user,
        uint256 amount
    ) public onlyRouter {
        RestrictedTokenLike token = RestrictedTokenLike(tranches[poolId][trancheId].token);
        require(address(token) != address(0), "CentrifugeConnector/unknown-token");
        require(token.hasMember(user), "CentrifugeConnector/not-a-member");
        token.mint(user, amount);
    }

    function transfer(
        uint64 poolId,
        bytes16 trancheId,
        address user,
        uint256 amount,
        Domain domainType,
        string memory domainName
    ) public {
        require(domainType == Domain.Parachain, "CentrifugeConnector/invalid-domain-type");
        require(keccak256(bytes(domainName)) == keccak256("centrifuge"), "CentrifugeConnector/invalid-domain-name");
        uint32 domainId = getDomain(Domain.Parachain, "centrifuge");
        RestrictedTokenLike token = RestrictedTokenLike(tranches[poolId][trancheId].token);
        require(address(token) != address(0), "CentrifugeConnector/unknown-token");
        require(token.balanceOf(user) >= amount, "CentrifugeConnector/insufficient-balance");
        require(token.transferFrom(user, address(this), amount), "CentrifugeConnector/token-transfer-failed");
        token.burn(address(this), amount);
        router.sendMessage(poolId, trancheId, amount, user);
    }
}
