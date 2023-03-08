// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.7.6;
pragma abicoder v2;

import {RestrictedTokenFactoryLike, MemberlistFactoryLike} from "./token/factory.sol";
import {RestrictedTokenLike} from "./token/restricted.sol";
import {MemberlistLike} from "./token/memberlist.sol";
// TODO: remove dependency on Messages.sol
import {ConnectorMessages} from "src/Messages.sol";

interface RouterLike {
    function send(bytes memory message) external;
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

    // --- Events ---
    event Rely(address indexed user);
    event Deny(address indexed user);
    event File(bytes32 indexed what, address data);
    event PoolAdded(uint256 indexed poolId);
    event TrancheAdded(uint256 indexed poolId, bytes16 indexed trancheId);
    event TrancheDeployed(uint256 indexed poolId, bytes16 indexed trancheId, address indexed token);

    constructor(address tokenFactory_, address memberlistFactory_) {
        tokenFactory = RestrictedTokenFactoryLike(tokenFactory_);
        memberlistFactory = MemberlistFactoryLike(memberlistFactory_);
        wards[msg.sender] = 1;
        emit Rely(msg.sender);
    }

    modifier auth() {
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

    function addTranche(
        uint64 poolId,
        bytes16 trancheId,
        string memory tokenName,
        string memory tokenSymbol,
        uint128 price
    ) public onlyRouter {
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

        address token = tokenFactory.newRestrictedToken(tranche.tokenName, tranche.tokenSymbol);
        tranche.token = token;

        address memberlist = memberlistFactory.newMemberlist();
        RestrictedTokenLike(token).depend("memberlist", memberlist);
        MemberlistLike(memberlist).updateMember(address(this), uint256(-1)); // required to be able to receive tokens in case of withdrawals
        emit TrancheDeployed(poolId, trancheId, token);
    }

    function updateTokenPrice(uint64 poolId, bytes16 trancheId, uint128 price) public onlyRouter {
        Tranche storage tranche = tranches[poolId][trancheId];
        require(tranche.lastPriceUpdate > 0, "CentrifugeConnector/invalid-pool-or-tranche");
        tranche.latestPrice = price;
        tranche.lastPriceUpdate = block.timestamp;
    }

    function updateMember(uint64 poolId, bytes16 trancheId, address user, uint64 validUntil) public onlyRouter {
        Tranche storage tranche = tranches[poolId][trancheId];
        require(tranche.lastPriceUpdate > 0, "CentrifugeConnector/invalid-pool-or-tranche");
        RestrictedTokenLike token = RestrictedTokenLike(tranche.token);
        MemberlistLike memberlist = MemberlistLike(token.memberlist());
        memberlist.updateMember(user, validUntil);
    }

    function handleTransfer(uint64 poolId, bytes16 trancheId, address destinationAddress, uint128 amount)
        public
        onlyRouter
    {
        // Lookup the tranche token
        RestrictedTokenLike token = RestrictedTokenLike(tranches[poolId][trancheId].token);
        require(address(token) != address(0), "CentrifugeConnector/unknown-token");

        // Ensure the destination address is a whitelisted member
        require(token.hasMember(destinationAddress), "CentrifugeConnector/not-a-member");

        // Mint the transfer amount to the destinationAddress account
        token.mint(destinationAddress, amount);
    }

    function transfer(
        uint64 poolId,
        bytes16 trancheId,
        ConnectorMessages.Domain domain,
        address destinationAddress,
        uint128 amount
    ) public {
        // Ensure the destination domain is supported
        require(domain == ConnectorMessages.Domain.Centrifuge, "CentrifugeConnector/invalid-domain");

        // Lookup the tranche token
        RestrictedTokenLike token = RestrictedTokenLike(tranches[poolId][trancheId].token);
        require(address(token) != address(0), "CentrifugeConnector/unknown-token");

        // Ensure the sender has enough balance and that the destination address is whitelisted
        require(token.balanceOf(msg.sender) >= amount, "CentrifugeConnector/insufficient-balance");
        // Burn the tokens
        token.burn(msg.sender, amount);

        // Send the Transfer message to the destination domain
        router.send(
            ConnectorMessages.formatTransfer(
                poolId, trancheId, ConnectorMessages.formatDomain(domain), destinationAddress, amount
            )
        );
    }
}
