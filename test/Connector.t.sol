// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.7.6;
pragma abicoder v2;

import { CentrifugeConnector } from "src/Connector.sol";
import { RestrictedTokenFactory } from "src/token/factory.sol";
import { MockHomeConnector } from "./mock/MockHomeConnector.sol";
import { ConnectorRouter } from "src/routers/nomad/Router.sol";
import "forge-std/Test.sol";

contract ConnectorTest is Test {

    CentrifugeConnector bridgedConnector;
    ConnectorRouter bridgedRouter;
    MockHomeConnector homeConnector;

    function setUp() public {
        address tokenFactory_ = address(new RestrictedTokenFactory());

        bridgedConnector = new CentrifugeConnector(address(this), tokenFactory_);
        bridgedRouter = new ConnectorRouter(address(bridgedConnector));
        bridgedConnector.file("router", address(bridgedRouter));

        homeConnector = new MockHomeConnector(address(bridgedRouter));
    }

    function testAddingPoolWorks(uint poolId) public {
        homeConnector.addPool(poolId);
        (uint actualPoolId) = bridgedConnector.pools(poolId);
        assertEq(actualPoolId, poolId);
    }

    function testAddingPoolAsNonRouterFails(uint poolId) public { }
    function testAddingTranchesWorks(uint poolId, string memory trancheId) public { }
    function testAddingTranchesAsNonRouterFails(uint poolId, string memory trancheId) public { }
    function testUpdatingMemberWorks(uint poolId) public { }
    function testUpdatingMemberAsNonRouterFails(uint poolId) public { }
    function testUpdatingMemberForNonExistentPoolFails(uint poolId) public { }
    function testUpdatingMemberForNonExistentTrancheFails(uint poolId) public { }
    function testUpdatingTokenPriceWorks(uint poolId) public { }
    function testUpdatingTokenPriceAsNonRouterFails(uint poolId) public { }
    function testUpdatingTokenPriceForNonExistentPoolFails(uint poolId) public { }
    function testUpdatingTokenPriceForNonExistentTrancheFails(uint poolId) public { }
    function testTransferToWorks(uint poolId) public { }
    function testTransferToAsNonRouterFails(uint poolId) public { }
    function testTransferToForNonExistentPoolFails(uint poolId) public { }
    function testTransferToForNonExistentTrancheFails(uint poolId) public { }

}