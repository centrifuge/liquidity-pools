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

    function testAddingPoolWorks(uint64 poolId) public {
        homeConnector.addPool(poolId);
        (uint64 actualPoolId,) = bridgedConnector.pools(poolId);
        assertEq(uint256(actualPoolId), uint256(poolId));
    }

    function testAddingPoolAsNonRouterFails(uint64 poolId) public { }

    function testAddingSingleTrancheWorks(uint64 poolId) public {
        homeConnector.addPool(poolId);
        (uint64 actualPoolId,) = bridgedConnector.pools(poolId);
        assertEq(uint256(actualPoolId), uint256(poolId));

        homeConnector.addTranche(poolId, new uint8[](16));
        // TODO: check tranche token existence
        assertEq(uint256(3), uint256(4));
    }

    function testAddingMultipleTranchesWorks(uint64 poolId, string memory trancheId) public {}
    
    function testAddingTranchesAsNonRouterFails(uint64 poolId, string memory trancheId) public { }
    function testUpdatingMemberWorks(uint64 poolId) public { }
    function testUpdatingMemberAsNonRouterFails(uint64 poolId) public { }
    function testUpdatingMemberForNonExistentPoolFails(uint64 poolId) public { }
    function testUpdatingMemberForNonExistentTrancheFails(uint64 poolId) public { }
    function testUpdatingTokenPriceWorks(uint64 poolId) public { }
    function testUpdatingTokenPriceAsNonRouterFails(uint64 poolId) public { }
    function testUpdatingTokenPriceForNonExistentPoolFails(uint64 poolId) public { }
    function testUpdatingTokenPriceForNonExistentTrancheFails(uint64 poolId) public { }
    function testTransferToWorks(uint64 poolId) public { }
    function testTransferToAsNonRouterFails(uint64 poolId) public { }
    function testTransferToForNonExistentPoolFails(uint64 poolId) public { }
    function testTransferToForNonExistentTrancheFails(uint64 poolId) public { }

}