// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.7.6;
pragma abicoder v2;

interface RouterLike {
  function updateInvestOrder(uint poolId, string calldata trancheId, uint amount) external;
  function updateRedeemOrder(uint poolId, string calldata trancheId, uint amount) external;
}

contract CentrifugeConnector {

  RouterLike public immutable router;

  struct Tranche {
    uint latestPrice; // [ray]
    address token;
  }

  struct Pool {
    uint poolId;
    mapping (string => Tranche) tranches;
  }
  
  mapping (uint => Pool) public pools;

  constructor(address router_) {
    router = RouterLike(router_);
  }

  modifier onlyRouter {
    require(msg.sender == address(router));
      _;
  }

  /** Investor interactions **/
  function updateInvestOrder(uint poolId, string calldata trancheId, uint amount) external {
    require(pools[poolId].poolId != 0, "unknown-pool");
    require(pools[poolId].tranches[trancheId].latestPrice != 0, "unknown-tranche");
    // TODO: check msg.sender is a member of the token

    router.updateInvestOrder(poolId, trancheId, amount);
  }

  function updateRedeemOrder(uint poolId, string calldata trancheId, uint amount) external { }

  /** Internal **/
  function addPool(uint poolId, string[] calldata trancheIds) public onlyRouter {
    Pool storage pool = pools[poolId];
    pool.poolId = poolId;

    for (uint i = 0; i < trancheIds.length; i++) {
      this.addTranche(poolId, trancheIds[i]);
    }
  }

  function addTranche(uint poolId, string calldata trancheId) public onlyRouter {
    // Deploy restricted token
    // Storage in tranche struct

  }

  function removeTranche(uint poolId, string calldata trancheId) public onlyRouter { }
  function updateTokenPrice(uint poolId, string calldata trancheId, uint price) public onlyRouter { }
  function updateMember(uint poolId, string calldata trancheId, address user, uint validUntil) public onlyRouter { }

}
