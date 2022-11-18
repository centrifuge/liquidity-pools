// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.7.6;
pragma abicoder v2;

import { CentrifugeConnector } from "src/Connector.sol";
import { RestrictedTokenFactory, MemberlistFactory } from "src/token/factory.sol";
import { RestrictedTokenLike } from "src/token/restricted.sol";
import { MemberlistLike, Memberlist } from "src/token/memberlist.sol";
import { MockHomeConnector } from "./mock/MockHomeConnector.sol";
import { ConnectorXCMRouter } from "src/routers/xcm/Router.sol";
import "forge-std/Test.sol";

contract ConnectorTest is Test {

    CentrifugeConnector bridgedConnector;
    ConnectorXCMRouter bridgedRouter;
    MockHomeConnector homeConnector;

    function setUp() public {
        address tokenFactory_ = address(new RestrictedTokenFactory());
        address memberlistFactory_ = address(new MemberlistFactory());

        bridgedConnector = new CentrifugeConnector(tokenFactory_, memberlistFactory_);
        bridgedRouter = new ConnectorXCMRouter(address(bridgedConnector), address(0));
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
        assertEq(token.name(), bytes32ToString(stringToBytes32(tokenName)));
        assertEq(token.symbol(), bytes32ToString(stringToBytes32(tokenSymbol)));
    }

    function testAddingMultipleTranchesWorks(uint64 poolId, bytes16[] calldata trancheIds, string memory tokenName, string memory tokenSymbol) public {
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

    function testUpdatingMemberWorks(uint64 poolId, bytes16 trancheId, address user, uint128 fuzzed_uint128) public {
        vm.assume(fuzzed_uint128 > 0);
        uint256 validUntil = safeAdd(fuzzed_uint128, safeAdd(block.timestamp, new Memberlist().minimumDelay()));
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
        vm.assume(validUntil <= safeAdd(block.timestamp, new Memberlist().minimumDelay()));
        vm.assume(user != address(0));

        homeConnector.addPool(poolId);
        homeConnector.addTranche(poolId, trancheId, "Some Name", "SYMBOL");
        vm.expectRevert("invalid-validUntil");
        homeConnector.updateMember(poolId, trancheId, user, validUntil);
    }

    function testUpdatingMemberAsNonRouterFails(uint64 poolId, bytes16 trancheId, address user, uint128 fuzzed_uint128) public {
        vm.assume(fuzzed_uint128 > 0);
        uint256 validUntil = safeAdd(fuzzed_uint128, safeAdd(block.timestamp, new Memberlist().minimumDelay()));
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

    function safeAdd(uint x, uint y) internal pure returns (uint z) {
        require((z = x + y) >= x, "math-add-overflow");
    }

    function stringToBytes32(string memory source) internal pure returns (bytes32 result) {
        bytes memory tempEmptyStringTest = bytes(source);
        if (tempEmptyStringTest.length == 0) {
            return 0x0;
        }

        assembly {
            result := mload(add(source, 32))
        }
    }

    function bytes32ToString(bytes32 _bytes32) internal returns (string memory) {
        uint8 i = 0;
        while(i < 32 && _bytes32[i] != 0) {
            i++;
        }

        bytes memory bytesArray = new bytes(i);
        for (i = 0; i < 32 && _bytes32[i] != 0; i++) {
            bytesArray[i] = _bytes32[i];
        }
        return string(bytesArray);
    }

}