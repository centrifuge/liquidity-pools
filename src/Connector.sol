// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.7.6;
pragma abicoder v2;

import { RestrictedTokenFactoryLike } from "./token/factory.sol";
import { RestrictedTokenLike } from "./token/restricted.sol";
import { MemberlistLike } from "./token/memberlist.sol";
import "forge-std/Test.sol";

interface RouterLike {
}

contract CentrifugeConnector is Test {

    RouterLike public router;
    RestrictedTokenFactoryLike public immutable tokenFactory;

    // --- Storage ---
    mapping(address => uint256) public wards;

    struct Tranche {
        uint256 latestPrice; // [ray]
        address token;
    }

    struct Pool {
        uint256 poolId;
        mapping(string => Tranche) tranches;
    }

    mapping(uint256 => Pool) public pools;

    // --- Events ---
    event Rely(address indexed user);
    event Deny(address indexed user);
    event File(bytes32 indexed what, address data);
    event PoolAdded(uint256 indexed poolId);
    event TrancheAdded(uint256 indexed poolId, string indexed trancheId, address indexed token);

    constructor(address router_, address tokenFactory_) {
        router = RouterLike(router_);
        tokenFactory = RestrictedTokenFactoryLike(tokenFactory_);
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
    function addPool(uint256 poolId) public onlyRouter {
        console.log("Adding a pool in Connector");
        Pool storage pool = pools[poolId];
        pool.poolId = poolId;
        emit PoolAdded(poolId);
    }

    function addTranche(uint256 poolId, string calldata trancheId)
        public
        onlyRouter
    {
        Pool storage pool = pools[poolId];
        Tranche storage tranche = pool.tranches[trancheId];

        // Deploy restricted token
        // TODO: set actual symbol and name
        tranche.token = tokenFactory.newRestrictedToken("SYMBOL", "Name");
        emit TrancheAdded(poolId, trancheId, tranche.token);
    }

    function updateTokenPrice(
        uint256 poolId,
        string calldata trancheId,
        uint256 price
    ) public onlyRouter {}

    function updateMember(
        uint256 poolId,
        string calldata trancheId,
        address user,
        uint256 validUntil
    ) public onlyRouter {
        RestrictedTokenLike token = RestrictedTokenLike(pools[poolId].tranches[trancheId].token);
        MemberlistLike memberlist = MemberlistLike(token.memberlist());
        memberlist.updateMember(user, validUntil);
    }

    function transferTo(
        uint256 poolId,
        string calldata trancheId,
        address user,
        uint256 amount
    ) public onlyRouter {
        RestrictedTokenLike token = RestrictedTokenLike(pools[poolId].tranches[trancheId].token);
        token.mint(user, amount);
    }
    
}
