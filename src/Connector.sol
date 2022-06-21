// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.7.6;
pragma abicoder v2;

import { RestrictedTokenFactoryLike, MemberlistFactoryLike } from "./token/factory.sol";
import { RestrictedTokenLike } from "./token/restricted.sol";
import { MemberlistLike } from "./token/memberlist.sol";
import "forge-std/Test.sol";

interface RouterLike {
}

contract CentrifugeConnector is Test {

    RouterLike public router;
    RestrictedTokenFactoryLike public immutable tokenFactory;
    MemberlistFactoryLike public immutable memberlistFactory;

    // --- Storage ---
    struct Pool {
        uint64 poolId;
        uint256 createdAt;
    }

    mapping(uint64 => Pool) public pools;

    struct Tranche {
        address token;
        uint256 latestPrice; // [ray]
        uint256 lastPriceUpdate;
    }

    mapping(uint64 => mapping(bytes16 => Tranche)) public tranches;

    mapping(address => uint256) public wards;

    // --- Events ---
    event Rely(address indexed user);
    event Deny(address indexed user);
    event File(bytes32 indexed what, address data);
    event PoolAdded(uint256 indexed poolId);
    event TrancheAdded(uint256 indexed poolId, bytes16 indexed trancheId, address indexed token);

    constructor(address router_, address tokenFactory_, address memberlistFactory_) {
        router = RouterLike(router_);
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

    // --- Internal ---
    function addPool(uint64 poolId) public onlyRouter {
        Pool storage pool = pools[poolId];
        pool.poolId = poolId;
        pool.createdAt = block.timestamp;
        emit PoolAdded(poolId);
    }

    function addTranche(uint64 poolId, bytes16 trancheId)
        public
        onlyRouter
    {
        Pool storage pool = pools[poolId];
        require(pool.createdAt > 0, "CentrifugeConnector/invalid-pool");

        Tranche storage tranche = tranches[poolId][trancheId];
        tranche.latestPrice = 1*10**27;

        // Deploy restricted token
        // TODO: set actual symbol and name
        address token = tokenFactory.newRestrictedToken("SYMBOL", "Name");
        tranche.token = token;

        address memberlist = memberlistFactory.newMemberlist();
        RestrictedTokenLike(token).depend("memberlist", memberlist);

        emit TrancheAdded(poolId, trancheId, token);
    }

    function updateTokenPrice(
        uint64 poolId,
        bytes16 trancheId,
        uint256 price
    ) public onlyRouter {}

    function updateMember(
        uint64 poolId,
        bytes16 trancheId,
        address user,
        uint256 validUntil
    ) public onlyRouter {
        RestrictedTokenLike token = RestrictedTokenLike(tranches[poolId][trancheId].token);
        MemberlistLike memberlist = MemberlistLike(token.memberlist());
        memberlist.updateMember(user, validUntil);
    }

    function transferTo(
        uint64 poolId,
        bytes16 trancheId,
        address user,
        uint256 amount
    ) public onlyRouter {
        RestrictedTokenLike token = RestrictedTokenLike(tranches[poolId][trancheId].token);
        require(token.hasMember(user), "CentrifugeConnector/not-a-member");
        token.mint(user, amount);
    }
    
}
