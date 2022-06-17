// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.7.6;
pragma abicoder v2;

import "forge-std/Test.sol";

interface RouterLike {
    function updateInvestOrder(
        uint256 poolId,
        string calldata trancheId,
        uint256 amount
    ) external;

    function updateRedeemOrder(
        uint256 poolId,
        string calldata trancheId,
        uint256 amount
    ) external;
}

contract CentrifugeConnector is Test {

    RouterLike public router;

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

    constructor(address router_) {
        router = RouterLike(router_);
        wards[msg.sender] = 1;
        emit Rely(msg.sender);
    }
    
    modifier auth {
        require(wards[msg.sender] == 1, "CentrifugeConnector/not-authorized");
        _;
    }

    modifier onlyRouter() {
        require(
            msg.sender == address(router),
            "CentrifugeConnector/not-authorized"
        );
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

    // --- Investor interactions ---
    function updateInvestOrder(
        uint256 poolId,
        string calldata trancheId,
        uint256 amount
    ) external {
        require(pools[poolId].poolId != 0, "CentrifugeConnector/unknown-pool");
        require(
            pools[poolId].tranches[trancheId].latestPrice != 0,
            "CentrifugeConnector/unknown-tranche"
        );
        // TODO: check msg.sender is a member of the token

        router.updateInvestOrder(poolId, trancheId, amount);
    }

    function updateRedeemOrder(
        uint256 poolId,
        string calldata trancheId,
        uint256 amount
    ) external {}

    // --- Internal ---
    // TOOD: add string[] calldata trancheIds
    function addPool(uint256 poolId) public onlyRouter {
        console.log("Adding a pool in Connector");
        Pool storage pool = pools[poolId];
        pool.poolId = poolId;

        // for (uint i = 0; i < trancheIds.length; i++) {
        //   this.addTranche(poolId, trancheIds[i]);
        // }

        emit PoolAdded(poolId);
    }

    function addTranche(uint256 poolId, string calldata trancheId)
        public
        onlyRouter
    {
        // Deploy restricted token
        // Storage in tranche struct
    }

    function removeTranche(uint256 poolId, string calldata trancheId)
        public
        onlyRouter
    {}

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
    ) public onlyRouter {}
}
