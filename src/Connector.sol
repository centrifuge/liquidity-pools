// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.7.6;

interface RouterLike {
  function updateInvestOrder(uint poolId, uint[] calldata trancheId, uint amount) external;
}

contract CentrifugeConnector {

  RouterLike public immutable router;

  constructor(address router_) {
    router = RouterLike(router_);
  }

  function updateInvestOrder(uint poolId, uint[] calldata trancheId, uint amount) external {
    // TODO: check pool_id is valid, check tranche_id is valid, transfer amount of pool currency to self
    router.updateInvestOrder(poolId, trancheId, amount);
  }

}
