// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.18;
pragma abicoder v2;

import {RestrictedTokenFactory, MemberlistFactory} from "src/token/factory.sol";
import "forge-std/Test.sol";

contract FactoryTest is Test {
    uint256 mainnetFork;

    // address(0)[0:20] + keccak("Centrifuge")[21:32]
    bytes32 SALT = 0x000000000000000000000000000000000000000075eb27011b69f002dc094d05;

    function setUp() public {}

    function testTokenAddressShouldBeDeterministic(address sender, uint64 chainId, string memory name, string memory symbol, uint8 decimals) public {
      vm.selectFork(mainnetFork = vm.createFork(vm.envString("RPC_URL")));
      vm.prank(sender);
      vm.chainId(uint256(chainId));

      RestrictedTokenFactory tokenFactory = new RestrictedTokenFactory{ salt: SALT }();
      assertEq(address(tokenFactory), 0xdD5DF939FA7DA2FFe2e4A16DDE56eb624B233D67);

      uint64 fixedPoolId = 1;
      bytes16 fixedTrancheId = "1";

      address token = tokenFactory.newRestrictedToken(fixedPoolId, fixedTrancheId, name, symbol, decimals);
      assertEq(address(token), 0xdD5DF939FA7DA2FFe2e4A16DDE56eb624B233D67);
    }
}
