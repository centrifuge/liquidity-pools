// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.7.6;
pragma abicoder v2;

import { CentrifugeConnector } from "src/Connector.sol";
import { RestrictedTokenFactory, MemberlistFactory } from "src/token/factory.sol";
import { RestrictedTokenLike } from "src/token/restricted.sol";
import { MemberlistLike, Memberlist } from "src/token/memberlist.sol";
import { MockHomeConnector } from "./mock/MockHomeConnector.sol";
import { ConnectorNomadRouter } from "src/routers/nomad/Router.sol";
import {Utils} from "src/Utils.sol";
import "forge-std/Test.sol";

contract ConnectorTest is Test {

    CentrifugeConnector bridgedConnector;
    ConnectorNomadRouter bridgedRouter;
    MockHomeConnector homeConnector;

    function setUp() public {
        address tokenFactory_ = address(new RestrictedTokenFactory());
        address memberlistFactory_ = address(new MemberlistFactory());

        bridgedConnector = new CentrifugeConnector(tokenFactory_, memberlistFactory_);
        // TODO: pass _xAppConnectionManager
        bridgedRouter = new ConnectorNomadRouter(address(bridgedConnector), address(0));
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

    function testAddingSingleTrancheWorks(uint64 poolId, bytes16 trancheId, string memory tokenName, string memory tokenSymbol) public {
        homeConnector.addPool(poolId);
        (uint64 actualPoolId,) = bridgedConnector.pools(poolId);
        assertEq(uint256(actualPoolId), uint256(poolId));

        homeConnector.addTranche(poolId, trancheId, tokenName, tokenSymbol);
        (address token_, uint256 latestPrice,) = bridgedConnector.tranches(poolId, trancheId);
        assertTrue(latestPrice > 0);
        assertTrue(token_ != address(0));

        RestrictedTokenLike token = RestrictedTokenLike(token_);
        // Comparing raw input to output can erroneously fail when a byte string is given. 
        // Intended behaviour is that byte strings will be treated as bytes and converted to strings instead of treated as strings themselves.
        // This conversion from string to bytes32 to string is used to simulate this intended behaviour.
        assertEq(token.name(), Utils.bytes32ToString(Utils.stringToBytes32(tokenName)));
        assertEq(token.symbol(), Utils.bytes32ToString(Utils.stringToBytes32(tokenSymbol)));
    }

    function testAddingMultipleTranchesWorks(uint64 poolId, bytes16[] calldata trancheIds, string memory tokenName, string memory tokenSymbol) public {
        vm.assume(trancheIds.length > 0 && trancheIds.length <= 5);

        homeConnector.addPool(poolId);

        for (uint i = 0; i < trancheIds.length; i++) {
            homeConnector.addTranche(poolId, trancheIds[i], tokenName, tokenSymbol);
            (address token, uint256 latestPrice,) = bridgedConnector.tranches(poolId, trancheIds[i]);
            assertTrue(latestPrice > 0);
            assertTrue(token != address(0));
        }
    }
    
    function testAddingTranchesAsNonRouterFails(uint64 poolId, bytes16 trancheId, string memory tokenName, string memory tokenSymbol) public {
        homeConnector.addPool(poolId);
        vm.expectRevert(bytes("CentrifugeConnector/not-the-router"));
        bridgedConnector.addTranche(poolId, trancheId, tokenName, tokenSymbol);
    }

    function testAddingTranchesForNonExistentPoolFails(uint64 poolId, bytes16 trancheId, string memory tokenName, string memory tokenSymbol) public {
        vm.expectRevert(bytes("CentrifugeConnector/invalid-pool"));
        homeConnector.addTranche(poolId, trancheId, tokenName, tokenSymbol);
    }

    function testUpdatingMemberWorks(uint64 poolId, bytes16 trancheId, address user, uint256 validUntil) public {
        vm.assume(validUntil > Utils.safeAdd(block.timestamp, new Memberlist().minimumDelay()));
        vm.assume(user != address(0));

        homeConnector.addPool(poolId);
        homeConnector.addTranche(poolId, trancheId, "Some Name", "SYMBOL");
        homeConnector.updateMember(poolId, trancheId, user, validUntil);

        (address token_,,) = bridgedConnector.tranches(poolId, trancheId);
        RestrictedTokenLike token = RestrictedTokenLike(token_);
        assertTrue(token.hasMember(user));

        MemberlistLike memberlist = MemberlistLike(token.memberlist());
        assertEq(memberlist.members(user), validUntil);
    }

    function testUpdatingMemberBeforeMinimumDelayFails(uint64 poolId, bytes16 trancheId, address user, uint256 validUntil) public {
        vm.assume(validUntil < Utils.safeAdd(block.timestamp, new Memberlist().minimumDelay()));
        vm.assume(user != address(0));

        homeConnector.addPool(poolId);
        homeConnector.addTranche(poolId, trancheId, "Some Name", "SYMBOL");
        vm.expectRevert("invalid-validUntil");
        homeConnector.updateMember(poolId, trancheId, user, validUntil);
    }

    function testUpdatingMemberAsNonRouterFails(uint64 poolId, bytes16 trancheId, address user, uint256 validUntil) public {
        vm.assume(validUntil > block.timestamp);
        vm.assume(user != address(0));

        vm.expectRevert(bytes("CentrifugeConnector/not-the-router"));
        bridgedConnector.updateMember(poolId, trancheId, user, validUntil);
    }

    function testUpdatingMemberForNonExistentPoolFails(uint64 poolId, bytes16 trancheId, address user, uint256 validUntil) public {
        vm.assume(validUntil > block.timestamp);
        vm.assume(user != address(0));
        bridgedConnector.file("router", address(this));
        vm.expectRevert(bytes("CentrifugeConnector/invalid-pool-or-tranche"));
        bridgedConnector.updateMember(poolId, trancheId, user, validUntil);
    }
    function testUpdatingMemberForNonExistentTrancheFails(uint64 poolId, bytes16 trancheId, address user, uint256 validUntil) public {
        vm.assume(validUntil > block.timestamp);
        vm.assume(user != address(0));
        bridgedConnector.file("router", address(this));
        bridgedConnector.addPool(poolId);
        vm.expectRevert(bytes("CentrifugeConnector/invalid-pool-or-tranche"));
        bridgedConnector.updateMember(poolId, trancheId, user, validUntil);  
     }

    function testUpdatingTokenPriceWorks(uint64 poolId, bytes16 trancheId, uint256 price) public {
        homeConnector.addPool(poolId);
        homeConnector.addTranche(poolId, trancheId, "Some Name", "SYMBOL");
        homeConnector.updateTokenPrice(poolId, trancheId, price);

        (, uint256 latestPrice, uint256 lastPriceUpdate) = bridgedConnector.tranches(poolId, trancheId);
        assertEq(latestPrice, price);
        assertEq(lastPriceUpdate, block.timestamp);
    }

    function testUpdatingTokenPriceAsNonRouterFails(uint64 poolId, bytes16 trancheId, uint256 price) public {
        homeConnector.addPool(poolId);
        homeConnector.addTranche(poolId, trancheId, "Some Name", "SYMBOL");
        vm.expectRevert(bytes("CentrifugeConnector/not-the-router"));
        bridgedConnector.updateTokenPrice(poolId, trancheId, price);

    }
    function testUpdatingTokenPriceForNonExistentPoolFails(uint64 poolId, bytes16 trancheId, uint256 price) public {
        bridgedConnector.file("router", address(this));
        vm.expectRevert(bytes("CentrifugeConnector/invalid-pool-or-tranche"));
        bridgedConnector.updateTokenPrice(poolId, trancheId, price);
     }
    function testUpdatingTokenPriceForNonExistentTrancheFails(uint64 poolId, bytes16 trancheId, uint256 price) public {
        bridgedConnector.file("router", address(this));
        bridgedConnector.addPool(poolId);
        vm.expectRevert(bytes("CentrifugeConnector/invalid-pool-or-tranche"));
        bridgedConnector.updateTokenPrice(poolId, trancheId, price);
     }

    function testTransferToWorks(uint64 poolId) public { }
    function testTransferToAsNonRouterFails(uint64 poolId) public { }
    function testTransferToForNonExistentPoolFails(uint64 poolId) public { }
    function testTransferToForNonExistentTrancheFails(uint64 poolId) public { }
}