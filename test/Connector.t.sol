// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.7.6;
pragma abicoder v2;

import { CentrifugeConnector } from "src/Connector.sol";
import { RestrictedTokenFactory, MemberlistFactory } from "src/token/factory.sol";
import { RestrictedTokenLike } from "src/token/restricted.sol";
import { MemberlistLike } from "src/token/memberlist.sol";
import { MockHomeConnector } from "./mock/MockHomeConnector.sol";
import { ConnectorRouter } from "src/routers/nomad/Router.sol";
import "forge-std/Test.sol";

contract ConnectorTest is Test {

    CentrifugeConnector bridgedConnector;
    ConnectorRouter bridgedRouter;
    MockHomeConnector homeConnector;

    function setUp() public {
        address tokenFactory_ = address(new RestrictedTokenFactory());
        address memberlistFactory_ = address(new MemberlistFactory());

        bridgedConnector = new CentrifugeConnector(address(this), tokenFactory_, memberlistFactory_);
        bridgedRouter = new ConnectorRouter(address(bridgedConnector));
        bridgedConnector.file("router", address(bridgedRouter));

        homeConnector = new MockHomeConnector(address(bridgedRouter));
    }

    function testAddingPoolWorks(uint64 poolId) public {
        homeConnector.addPool(poolId);
        (uint64 actualPoolId,) = bridgedConnector.pools(poolId);
        assertEq(uint256(actualPoolId), uint256(poolId));
    }

    function testAddingPoolAsNonRouterFails(uint64 poolId) public {
        vm.expectRevert(bytes("CentrifugeConnector/not-the-router"));
        bridgedConnector.addPool(poolId);
    }

    function testAddingSingleTrancheWorks(uint64 poolId, bytes16 trancheId) public {
        homeConnector.addPool(poolId);
        (uint64 actualPoolId,) = bridgedConnector.pools(poolId);
        assertEq(uint256(actualPoolId), uint256(poolId));

        homeConnector.addTranche(poolId, trancheId);
        (address token, uint256 latestPrice,) = bridgedConnector.tranches(poolId, trancheId);
        assertTrue(latestPrice > 0);
        assertTrue(token != address(0));
    }

    function testAddingMultipleTranchesWorks(uint64 poolId, bytes16[] calldata trancheIds) public {
        vm.assume(trancheIds.length > 0 && trancheIds.length <= 5);

        homeConnector.addPool(poolId);

        for (uint i = 0; i < trancheIds.length; i++) {
            homeConnector.addTranche(poolId, trancheIds[i]);
            (address token, uint256 latestPrice,) = bridgedConnector.tranches(poolId, trancheIds[i]);
            assertTrue(latestPrice > 0);
            assertTrue(token != address(0));
        }
    }
    
    function testAddingTranchesAsNonRouterFails(uint64 poolId, bytes16 trancheId) public {
        homeConnector.addPool(poolId);
        vm.expectRevert(bytes("CentrifugeConnector/not-the-router"));
        bridgedConnector.addTranche(poolId, trancheId);
    }

    function testAddingTranchesForNonExistentPoolFails(uint64 poolId, bytes16 trancheId) public {
        vm.expectRevert(bytes("CentrifugeConnector/invalid-pool"));
        homeConnector.addTranche(poolId, trancheId);
    }

    function testUpdatingMemberWorks(uint64 poolId, bytes16 trancheId, address user, uint256 validUntil) public {
        vm.assume(validUntil > block.timestamp);
        vm.assume(user != address(0));

        homeConnector.addPool(poolId);
        homeConnector.addTranche(poolId, trancheId);
        homeConnector.updateMember(poolId, trancheId, user, validUntil);

        (address token_,,) = bridgedConnector.tranches(poolId, trancheId);
        RestrictedTokenLike token = RestrictedTokenLike(token_);
        assertTrue(token.hasMember(user));

        MemberlistLike memberlist = MemberlistLike(token.memberlist());
        assertEq(memberlist.members(user), validUntil);
    }

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

    // function setupPool() internal returns (uint64 poolId, bytes16[] trancheIds) {
    //     uint64 poolId = 1;
    //     bytes16[] trancheIds = new bytes16[]();
    //     homeConnector.addPool(poolId);
    //     homeConnector.addTranche(poolId, trancheId);
    // }

}