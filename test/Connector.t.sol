// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.7.6;
pragma abicoder v2;

import { CentrifugeConnector } from "src/Connector.sol";
import { RestrictedTokenFactory, MemberlistFactory } from "src/token/factory.sol";
import { RestrictedTokenLike } from "src/token/restricted.sol";
import { MemberlistLike, Memberlist } from "src/token/memberlist.sol";
import { MockHomeConnector } from "./mock/MockHomeConnector.sol";
import { ConnectorXCMRouter } from "src/routers/xcm/Router.sol";
import {ConnectorMessages} from "src/Messages.sol";
import "forge-std/Test.sol";
import "../src/Connector.sol";

contract ConnectorTest is Test {

    CentrifugeConnector bridgedConnector;
    ConnectorXCMRouter bridgedRouter;
    MockHomeConnector homeConnector;

    uint minimumDelay;

    function setUp() public {
        address tokenFactory_ = address(new RestrictedTokenFactory());
        address memberlistFactory_ = address(new MemberlistFactory());

        bridgedConnector = new CentrifugeConnector(tokenFactory_, memberlistFactory_);
        homeConnector = new MockHomeConnector(address(bridgedConnector));
        bridgedConnector.file("router", address(homeConnector.router()));
        minimumDelay =  new Memberlist().minimumDelay();
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

    function testAddingSingleTrancheWorks(uint64 poolId, string memory tokenName, string memory tokenSymbol, bytes16 trancheId, uint128 price) public {
        // 0. Add Pool
        homeConnector.addPool(poolId);
        (uint64 actualPoolId,) = bridgedConnector.pools(poolId);
        assertEq(uint256(actualPoolId), uint256(poolId));

        // 1. Add the tranche
        homeConnector.addTranche(poolId, trancheId, tokenName, tokenSymbol, price);
        // 2. Then deploy the tranche
        bridgedConnector.deployTranche(poolId, trancheId);

        (address token_, uint256 latestPrice,,string memory actualTokenName, string memory actualTokenSymbol)
            = bridgedConnector.tranches(poolId, trancheId);
        assertTrue(token_ != address(0));
        assertEq(latestPrice, price);

        // Comparing raw input to output can erroneously fail when a byte string is given.
        // Intended behaviour is that byte strings will be treated as bytes and converted to strings
        // instead of treated as strings themselves. This conversion from string to bytes32 to string
        // is used to simulate this intended behaviour.
        assertEq(actualTokenName, bytes32ToString(stringToBytes32(tokenName)));
        assertEq(actualTokenSymbol, bytes32ToString(stringToBytes32(tokenSymbol)));

        RestrictedTokenLike token = RestrictedTokenLike(token_);
        assertEq(token.name(), bytes32ToString(stringToBytes32(tokenName)));
        assertEq(token.symbol(), bytes32ToString(stringToBytes32(tokenSymbol)));
    }

    function testAddingMultipleTranchesWorks(uint64 poolId, bytes16[] calldata trancheIds, string memory tokenName, string memory tokenSymbol, uint128 price) public {
        homeConnector.addPool(poolId);

        for (uint i = 0; i < trancheIds.length; i++) {
            uint128 tranchePrice = price + uint128(i);
            homeConnector.addTranche(poolId, trancheIds[i], tokenName, tokenSymbol, tranchePrice);
            bridgedConnector.deployTranche(poolId, trancheIds[i]);
            (address token, uint256 latestPrice, , ,) = bridgedConnector.tranches(poolId, trancheIds[i]);
            assertEq(latestPrice, tranchePrice);
            assertTrue(token != address(0));
        }
    }
    
    function testAddingTranchesAsNonRouterFails(uint64 poolId, bytes16 trancheId, string memory tokenName, string memory tokenSymbol, uint128 price) public {
        homeConnector.addPool(poolId);
        vm.expectRevert(bytes("CentrifugeConnector/not-the-router"));
        bridgedConnector.addTranche(poolId, trancheId, tokenName, tokenSymbol, price);
    }

    function testAddingTranchesForNonExistentPoolFails(uint64 poolId, bytes16 trancheId, string memory tokenName, string memory tokenSymbol, uint128 price) public {
        vm.expectRevert(bytes("CentrifugeConnector/invalid-pool"));
        homeConnector.addTranche(poolId, trancheId, tokenName, tokenSymbol, price);
    }

    function testUpdatingMemberWorks(uint64 poolId, bytes16 trancheId, address user, uint64 validUntil) public {
        vm.assume(validUntil >= safeAdd(block.timestamp, new Memberlist().minimumDelay()));
        vm.assume(user != address(0));

        homeConnector.addPool(poolId);
        homeConnector.addTranche(poolId, trancheId, "Some Name", "SYMBOL", 123);
        bridgedConnector.deployTranche(poolId, trancheId);
        homeConnector.updateMember(poolId, trancheId, user, validUntil);

        (address token_,,,,) = bridgedConnector.tranches(poolId, trancheId);
        RestrictedTokenLike token = RestrictedTokenLike(token_);
        assertTrue(token.hasMember(user));

        MemberlistLike memberlist = MemberlistLike(token.memberlist());
        assertEq(memberlist.members(user), validUntil);
    }

    function testUpdatingMemberBeforeMinimumDelayFails(uint64 poolId, bytes16 trancheId, address user, uint64 validUntil) public {
        vm.assume(validUntil <= safeAdd(block.timestamp, new Memberlist().minimumDelay()));
        vm.assume(user != address(0));

        homeConnector.addPool(poolId);
        homeConnector.addTranche(poolId, trancheId, "Some Name", "SYMBOL", 123);
        bridgedConnector.deployTranche(poolId, trancheId);
        vm.expectRevert("invalid-validUntil");
        homeConnector.updateMember(poolId, trancheId, user, validUntil);
    }

    function testUpdatingMemberAsNonRouterFails(uint64 poolId, bytes16 trancheId, address user, uint64 validUntil) public {
        vm.assume(validUntil <= safeAdd(block.timestamp, new Memberlist().minimumDelay()));
        vm.assume(user != address(0));

        vm.expectRevert(bytes("CentrifugeConnector/not-the-router"));
        bridgedConnector.updateMember(poolId, trancheId, user, validUntil);
    }

    function testUpdatingMemberForNonExistentPoolFails(uint64 poolId, bytes16 trancheId, address user, uint64 validUntil) public {
        vm.assume(validUntil > block.timestamp);
        bridgedConnector.file("router", address(this));
        vm.expectRevert(bytes("CentrifugeConnector/invalid-pool-or-tranche"));
        bridgedConnector.updateMember(poolId, trancheId, user, validUntil);
    }


    function testUpdatingMemberForNonExistentTrancheFails(uint64 poolId, bytes16 trancheId, address user, uint64 validUntil) public {
        vm.assume(validUntil > block.timestamp);
        bridgedConnector.file("router", address(this));
        bridgedConnector.addPool(poolId);
        vm.expectRevert(bytes("CentrifugeConnector/invalid-pool-or-tranche"));
        bridgedConnector.updateMember(poolId, trancheId, user, validUntil);  
     }


    function testUpdatingTokenPriceWorks(uint64 poolId, bytes16 trancheId, uint256 price) public {
        homeConnector.addPool(poolId);
        homeConnector.addTranche(poolId, trancheId, "Some Name", "SYMBOL", 123);
        homeConnector.updateTokenPrice(poolId, trancheId, price);

        (, uint256 latestPrice, uint256 lastPriceUpdate, ,) = bridgedConnector.tranches(poolId, trancheId);
        assertEq(latestPrice, price);
        assertEq(lastPriceUpdate, block.timestamp);
    }

    function testUpdatingTokenPriceAsNonRouterFails(uint64 poolId, bytes16 trancheId, uint256 price) public {
        homeConnector.addPool(poolId);
        homeConnector.addTranche(poolId, trancheId, "Some Name", "SYMBOL", 123);
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

    // helpers 
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

    function bytes32ToString(bytes32 _bytes32) internal pure returns (string memory) {
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

    function toBytes32(bytes memory f) internal pure returns (bytes16 fc) {
        assembly {
          fc := mload(add(f, 32))
        }
        return fc;
    }

    function toBytes29(bytes memory f) internal pure returns (bytes29 fc) {
        assembly {
          fc := mload(add(f, 29))
        }
        return fc;
    }

}

 
