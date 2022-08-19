// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.7.6;
pragma abicoder v2;

import { CentrifugeConnector } from "src/Connector.sol";
import { RestrictedTokenFactory, MemberlistFactory } from "src/token/factory.sol";
import { RestrictedTokenLike } from "src/token/restricted.sol";
import { MemberlistLike, Memberlist } from "src/token/memberlist.sol";
import { MockHomeConnector } from "./mock/MockHomeConnector.sol";
import { ConnectorXCMRouter } from "src/routers/xcm/Router.sol";
import { XAppConnectionManager } from "@nomad-xyz/contracts-core/contracts/XAppConnectionManager.sol";
import {ConnectorMessages} from "src/Messages.sol";
import "forge-std/Test.sol";

contract ConnectorTest is Test {

    CentrifugeConnector bridgedConnector;
    ConnectorXCMRouter bridgedRouter;
    MockHomeConnector homeConnector;

    uint minimumDelay;

    function setUp() public {
        address tokenFactory_ = address(new RestrictedTokenFactory());
        address memberlistFactory_ = address(new MemberlistFactory());

        bridgedConnector = new CentrifugeConnector(tokenFactory_, memberlistFactory_);

        // home = new Home(1000);
        homeConnector = new MockHomeConnector();
        XAppConnectionManager connectionManager = new XAppConnectionManager(); 
        connectionManager.setHome(address(homeConnector));

        bridgedRouter = new ConnectorXCMRouter(address(bridgedConnector), address(homeConnector), address(connectionManager));
        homeConnector.setRouter(address(bridgedRouter));
        bridgedConnector.file("router", address(bridgedRouter)); 

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
        vm.assume(validUntil > safeAdd(block.timestamp, minimumDelay));
        homeConnector.addPool(poolId);
        homeConnector.addTranche(poolId, trancheId, "Some Name", "SYMBOL");
        homeConnector.updateMember(poolId, trancheId, user, validUntil);

        (address token_,,) = bridgedConnector.tranches(poolId, trancheId);
        RestrictedTokenLike token = RestrictedTokenLike(token_);
        assertTrue(token.hasMember(user));

        MemberlistLike memberlist = MemberlistLike(token.memberlist());
        assertEq(memberlist.members(user), validUntil);
    }

    function testUpdatingMemberAsNonRouterFails(uint64 poolId, bytes16 trancheId, address user, uint256 validUntil) public {
        vm.assume(validUntil > block.timestamp);

        vm.expectRevert(bytes("CentrifugeConnector/not-the-router"));
        bridgedConnector.updateMember(poolId, trancheId, user, validUntil);
    }

    function testUpdatingMemberForNonExistentPoolFails(uint64 poolId, bytes16 trancheId, address user, uint256 validUntil) public {
        vm.assume(validUntil > block.timestamp);
        bridgedConnector.file("router", address(this));
        vm.expectRevert(bytes("CentrifugeConnector/invalid-pool-or-tranche"));
        bridgedConnector.updateMember(poolId, trancheId, user, validUntil);
    }

    function testUpdatingMemberBeforeMinimumDelayFails(uint64 poolId, bytes16 trancheId, address user, uint256 validUntil) public {
        vm.assume(validUntil < safeAdd(block.timestamp, minimumDelay)); 
        homeConnector.addPool(poolId);
        homeConnector.addTranche(poolId, trancheId, "Some Name", "SYMBOL");
        homeConnector.updateMember(poolId, trancheId, user, validUntil);

        vm.expectRevert(bytes("invalid-validUntil"));
    }

    function testUpdatingMemberForNonExistentTrancheFails(uint64 poolId, bytes16 trancheId, address user, uint256 validUntil) public {
        vm.assume(validUntil > block.timestamp);
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
    
    function testTransferWorks(uint64 poolId, bytes16 trancheId, address user, uint256 amount, uint256 validUntil) public {
        vm.assume(validUntil > safeAdd(block.timestamp, minimumDelay));

        homeConnector.addPool(poolId);
        homeConnector.addTranche(poolId, trancheId, "Some Name", "SYMBOL");
        homeConnector.updateMember(poolId, trancheId, user, validUntil);

        (address token_,,) = bridgedConnector.tranches(poolId, trancheId);
        RestrictedTokenLike token = RestrictedTokenLike(token_);
        MemberlistLike memberlist = MemberlistLike(token.memberlist());
        uint totalSupplyBefore = token.totalSupply();

        homeConnector.transfer(poolId, trancheId, user, amount);

        assertEq(memberlist.members(user), validUntil);
        assertTrue(token.hasMember(user));
        assertEq(token.balanceOf(user), amount);
        assertEq(token.totalSupply(), safeAdd(totalSupplyBefore, amount));
     }

    function testTransferForNonExistentPoolFails(uint64 poolId, bytes16 trancheId, address user, uint256 amount, uint256 validUntil) public { 
        vm.assume(validUntil > safeAdd(block.timestamp, minimumDelay));

        // do not add pool
        vm.expectRevert(bytes("CentrifugeConnector/invalid-pool"));
        homeConnector.addTranche(poolId, trancheId, "Some Name", "SYMBOL");
        
        vm.expectRevert(bytes("CentrifugeConnector/invalid-pool-or-tranche"));
        homeConnector.updateMember(poolId, trancheId, user, validUntil);

        vm.expectRevert(bytes("CentrifugeConnector/unknown-token"));
        homeConnector.transfer(poolId, trancheId, user, amount);
    }
    
    function testTransferForNonExistentTrancheFails(uint64 poolId, bytes16 trancheId, address user, uint256 amount, uint256 validUntil) public { 
        vm.assume(validUntil > safeAdd(block.timestamp, minimumDelay));

        homeConnector.addPool(poolId);
        //do not add tranche
        vm.expectRevert(bytes("CentrifugeConnector/invalid-pool-or-tranche"));
        homeConnector.updateMember(poolId, trancheId, user, validUntil);

        vm.expectRevert(bytes("CentrifugeConnector/unknown-token"));        homeConnector.transfer(poolId, trancheId, user, amount);
    
    }

    function testTransferForNoMemberlistFails(uint64 poolId, bytes16 trancheId, address user, uint256 amount, uint256 validUntil) public { 
        vm.assume(validUntil > safeAdd(block.timestamp, minimumDelay));

        homeConnector.addPool(poolId);
        homeConnector.addTranche(poolId, trancheId, "Some Name", "SYMBOL");

        // do not add to Memberlist
        vm.expectRevert(bytes("CentrifugeConnector/not-a-member"));
        homeConnector.transfer(poolId, trancheId, user, amount);
    }

    function testTransferFromOtherOriginFails(uint64 poolId, bytes16 trancheId, address user, uint256 amount, uint256 validUntil) public { 

        MockHomeConnector homeConnectorDifferentOrigin = new MockHomeConnector();
        homeConnectorDifferentOrigin.setRouter(address(bridgedRouter));
         vm.assume(validUntil > safeAdd(block.timestamp, minimumDelay));

        homeConnector.addPool(poolId);
        homeConnector.addTranche(poolId, trancheId, "Some Name", "SYMBOL");
        homeConnector.updateMember(poolId, trancheId, user, validUntil);

        vm.expectRevert(bytes("ConnectorXCMRouter/invalid-origin"));
        homeConnectorDifferentOrigin.transfer(poolId, trancheId, user, amount);
    }

  
    function testWithdrawalWorks(uint64 poolId, bytes16 trancheId, uint256 amount, address user) public { 
        string memory domainName = "Centrifuge";
        uint32 domainId = 3000;
        bytes32 recipient = stringToBytes32("0xefc56627233b02ea95bae7e19f648d7dcd5bb132");
        // add Centrifuge domain to router                  
        bridgedRouter.enrollRemoteRouter(domainId, recipient);
        
        // add Centrifuge domain to connector
        assertEq(bridgedConnector.wards(address(this)), 1);
        bridgedConnector.file("domain", domainName, domainId);
        bridgedConnector.deny(address(this)); // revoke ward permissions to test public functions
        
        user = address(this); // set deployer as user to approve the cnnector to transfer funds
        
        // fund user
        homeConnector.addPool(poolId);
        homeConnector.addTranche(poolId, trancheId, "Some Name", "SYMBOL");
        homeConnector.updateMember(poolId, trancheId, user, uint(-1));
        homeConnector.transfer(poolId, trancheId, user, amount);
        // approve token
        (address token_,,) = bridgedConnector.tranches(poolId, trancheId);
        RestrictedTokenLike token = RestrictedTokenLike(token_);
        token.approve(address(bridgedConnector), uint(-1)); // approve connector to take token

        uint userTokenBalanceBefore = token.balanceOf(user);

        // withdraw
        bridgedConnector.withdraw(poolId, trancheId, user, amount, domainName);
        
        assert(homeConnector.dispatchDomain() == domainId);
        assertEq(token.balanceOf(user), (userTokenBalanceBefore - amount));
        assertEq(homeConnector.dispatchRecipient(), recipient);
        assertEq(homeConnector.dispatchCalls(), 1);

        // TODO: fix assertions
        //(uint64 poolIdDispatchCall, bytes16 trancheIdDispatchCall, address userDispatchCall, uint256 amountDispatchCall) =  ConnectorMessages.parseTransfer(toBytes29(homeConnector.dispatchMessage()));
        // assert(poolIdDispatchCall == poolId);
        // assertEq(trancheIdDispatchCall,trancheId);
        // assertEq(userDispatchCall, user);
        // assertEq(amountDispatchCall, amount);
    }


    // function testWithdrawalFailsUnknownDomainConnector(uint64 poolId) public { }
    // function testWithdrawalFailsUnknownDomainRouter(uint64 poolId) public { }
    // function testWithdrawalFailsUNoPermissions(uint64 poolId) public { }
    // function testWithdrawalFailsNotConnector(uint64 poolId) public { }
    // function testWithdrawalFailsNotEnoughBalance(uint64 poolId) public { }
    // function testWithdrawalFailsNotEnoughBalance(uint64 poolId) public { }
    // function testWithdrawalFailsPoolDoesNotExist(uint64 poolId) public { }
    // function fails domain does not exist


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

    // Convert an hexadecimal string to raw bytes
    function fromHex(string memory s) internal pure returns (bytes memory) {
        bytes memory ss = bytes(s);
        require(ss.length % 2 == 0); // length must be even
        bytes memory r = new bytes(ss.length / 2);

        for (uint256 i = 0; i < ss.length / 2; ++i) {
            r[i] = bytes1(
                fromHexChar(uint8(ss[2 * i])) *
                    16 +
                    fromHexChar(uint8(ss[2 * i + 1]))
            );
        }
        return r;
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

   // Convert an hexadecimal character to their value
    function fromHexChar(uint8 c) internal pure returns (uint8) {
        if (bytes1(c) >= bytes1("0") && bytes1(c) <= bytes1("9")) {
            return c - uint8(bytes1("0"));
        }
        if (bytes1(c) >= bytes1("a") && bytes1(c) <= bytes1("f")) {
            return 10 + c - uint8(bytes1("a"));
        }
        if (bytes1(c) >= bytes1("A") && bytes1(c) <= bytes1("F")) {
            return 10 + c - uint8(bytes1("A"));
        }
        revert("Failed to encode hex char");
    }
}

 