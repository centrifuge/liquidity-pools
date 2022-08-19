// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.7.6;
pragma abicoder v2;

import { RestrictedTokenFactoryLike, MemberlistFactoryLike } from "./token/factory.sol";
import { RestrictedTokenLike } from "./token/restricted.sol";
import { MemberlistLike } from "./token/memberlist.sol";

interface RouterLike {
    function sendMessage(uint32 destinationDomain, uint64 poolId, bytes16 trancheId, uint256 amount, address user) external;
}

contract CentrifugeConnector {

    RouterLike public router;
    RestrictedTokenFactoryLike public immutable tokenFactory;
    MemberlistFactoryLike public immutable memberlistFactory;

    // --- Storage ---
    struct Pool {
        uint64 poolId;
        uint256 createdAt;
    }

    struct Tranche {
        address token;
        uint256 latestPrice; // [ray]
        uint256 lastPriceUpdate;
    }

    mapping(uint64 => Pool) public pools;
    mapping(uint64 => mapping(bytes16 => Tranche)) public tranches;
    mapping(address => uint256) public wards;
    mapping(bytes32 => uint32) public domainLookup;


    // --- Events ---
    event Rely(address indexed user);
    event Deny(address indexed user);
    event File(bytes32 indexed what, address data);
    event File(bytes32 indexed what, string data);
    event PoolAdded(uint256 indexed poolId);
    event TrancheAdded(uint256 indexed poolId, bytes16 indexed trancheId, address indexed token);

    constructor(address tokenFactory_, address memberlistFactory_) {
        tokenFactory = RestrictedTokenFactoryLike(tokenFactory_);
        memberlistFactory = MemberlistFactoryLike(memberlistFactory_);
        wards[msg.sender] = 1;
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
        if(name == "domain") {
           domainLookup[keccak256(bytes(domainName))] = domainId;
           emit File(name, domainName);
        } else { revert ("unknown name");}
        
    }

    // --- Internal ---
    function addPool(uint64 poolId) public onlyRouter {
        Pool storage pool = pools[poolId];
        pool.poolId = poolId;
        pool.createdAt = block.timestamp;
        emit PoolAdded(poolId);
    }

    function addTranche(uint64 poolId, bytes16 trancheId, string memory tokenName, string memory tokenSymbol)
        public
        onlyRouter
    {
        Pool storage pool = pools[poolId];
        require(pool.createdAt > 0, "CentrifugeConnector/invalid-pool");

        Tranche storage tranche = tranches[poolId][trancheId];
        tranche.latestPrice = 1*10**27;

        address token = tokenFactory.newRestrictedToken(tokenName, tokenSymbol);
        tranche.token = token;

        address memberlist = memberlistFactory.newMemberlist();
        RestrictedTokenLike(token).depend("memberlist", memberlist);
        MemberlistLike(memberlist).updateMember(address(this), uint(-1)); // required to be able to receive tokens in case of withdrawals   
        emit TrancheAdded(poolId, trancheId, token);
    }

    function updateTokenPrice(
        uint64 poolId,
        bytes16 trancheId,
        uint256 price
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
        uint256 validUntil
    ) public onlyRouter {
        Tranche storage tranche = tranches[poolId][trancheId];
        require(tranche.latestPrice > 0, "CentrifugeConnector/invalid-pool-or-tranche");
        RestrictedTokenLike token = RestrictedTokenLike(tranche.token);
        MemberlistLike memberlist = MemberlistLike(token.memberlist());
        memberlist.updateMember(user, validUntil);
    }

    function transfer(
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

    function transferTo(
        uint64 poolId,
        bytes16 trancheId,
        address user,
        uint256 amount,
        string memory domainName
    ) public {
        uint32 domainId = domainLookup[keccak256(bytes(domainName))];
        require(domainId > 0, "CentrifugeConnector/domain-does-not-exist");

        RestrictedTokenLike token = RestrictedTokenLike(tranches[poolId][trancheId].token);
        require(address(token) != address(0), "CentrifugeConnector/unknown-token");
        require(token.balanceOf(user) >= amount, "CentrifugeConnector/insufficient-balance");
        require(token.transferFrom(user, address(this), amount), "CentrifugeConnector/token-transfer-failed");
        token.burn(address(this), amount);
        router.sendMessage(domainId, poolId, trancheId, amount, user);
    }
}
