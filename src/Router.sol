// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.7.6;

import "forge-std/Test.sol";

contract Router is Test {

  function updateInvestOrder(uint poolId, uint[] calldata trancheId, uint amount) external {
    console.log(poolId);
    console.log(amount);
    // TODO: send message to Nomad Home contract
    return;
  }

}
