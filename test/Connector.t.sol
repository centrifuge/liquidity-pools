// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.18;
pragma abicoder v2;

import {CentrifugeConnector} from "src/Connector.sol";
import {ConnectorGateway} from "src/routers/Gateway.sol";
import {ConnectorEscrow} from "src/Escrow.sol";
import {RestrictedTokenFactory, MemberlistFactory} from "src/token/factory.sol";
import {RestrictedTokenLike} from "src/token/restricted.sol";
import {MemberlistLike, Memberlist} from "src/token/memberlist.sol";
import {MockHomeConnector} from "./mock/MockHomeConnector.sol";
import {MockXcmRouter} from "./mock/MockXcmRouter.sol";
import "forge-std/Test.sol";
import "../src/Connector.sol";

contract ConnectorTest is Test {
    CentrifugeConnector bridgedConnector;
    ConnectorGateway gateway;
    MockHomeConnector connector;
    MockXcmRouter mockXcmRouter;

    function setUp() public {
        vm.chainId(1);
        address escrow_ = address(new ConnectorEscrow());
        address tokenFactory_ = address(new RestrictedTokenFactory());
        address memberlistFactory_ = address(new MemberlistFactory());

        bridgedConnector = new CentrifugeConnector(escrow_, tokenFactory_, memberlistFactory_);
        mockXcmRouter = new MockXcmRouter(address(bridgedConnector));

        connector = new MockHomeConnector(address(mockXcmRouter));
        gateway = new ConnectorGateway(address(bridgedConnector), address(mockXcmRouter));
        bridgedConnector.file("gateway", address(gateway));
        mockXcmRouter.file("gateway", address(gateway));
    }

    function testAddingPoolWorks(uint64 poolId) public {
        connector.addPool(poolId);
        (uint64 actualPoolId,,) = bridgedConnector.pools(poolId);
        assertEq(uint256(actualPoolId), uint256(poolId));
    }

    function testAddingPoolAsNonRouterFails(uint64 poolId) public {
        vm.expectRevert(bytes("CentrifugeConnector/not-the-gateway"));
        bridgedConnector.addPool(poolId);
    }

    function testAddingSingleTrancheWorks(
        uint64 poolId,
        string memory tokenName,
        string memory tokenSymbol,
        bytes16 trancheId,
        uint128 price
    ) public {
        connector.addPool(poolId);
        (uint64 actualPoolId,,) = bridgedConnector.pools(poolId);
        assertEq(uint256(actualPoolId), uint256(poolId));

        connector.addTranche(poolId, trancheId, tokenName, tokenSymbol, price);
        bridgedConnector.deployTranche(poolId, trancheId);

        (address token_, uint256 latestPrice,, string memory actualTokenName, string memory actualTokenSymbol) =
            bridgedConnector.tranches(poolId, trancheId);
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

    function testAddingMultipleTranchesWorks(
        uint64 poolId,
        bytes16[] calldata trancheIds,
        string memory tokenName,
        string memory tokenSymbol,
        uint128 price
    ) public {
        connector.addPool(poolId);

        for (uint256 i = 0; i < trancheIds.length; i++) {
            connector.addTranche(poolId, trancheIds[i], tokenName, tokenSymbol, price);
            bridgedConnector.deployTranche(poolId, trancheIds[i]);
            (address token, uint256 latestPrice,,,) = bridgedConnector.tranches(poolId, trancheIds[i]);
            assertEq(latestPrice, price);
            assertTrue(token != address(0));
        }
    }

    function testAddingTranchesAsNonRouterFails(
        uint64 poolId,
        bytes16 trancheId,
        string memory tokenName,
        string memory tokenSymbol,
        uint128 price
    ) public {
        connector.addPool(poolId);
        vm.expectRevert(bytes("CentrifugeConnector/not-the-gateway"));
        bridgedConnector.addTranche(poolId, trancheId, tokenName, tokenSymbol, price);
    }

    function testAddingTranchesForNonExistentPoolFails(
        uint64 poolId,
        bytes16 trancheId,
        string memory tokenName,
        string memory tokenSymbol,
        uint128 price
    ) public {
        vm.expectRevert(bytes("CentrifugeConnector/invalid-pool"));
        connector.addTranche(poolId, trancheId, tokenName, tokenSymbol, price);
    }

    function testDeployingWrongTrancheFails(
        uint64 poolId,
        string memory tokenName,
        string memory tokenSymbol,
        bytes16 trancheId,
        bytes16 wrongTrancheId,
        uint128 price
    ) public {
        vm.assume(trancheId != wrongTrancheId);

        connector.addPool(poolId);
        (uint64 actualPoolId,,) = bridgedConnector.pools(poolId);
        assertEq(uint256(actualPoolId), uint256(poolId));

        connector.addTranche(poolId, trancheId, tokenName, tokenSymbol, price);
        vm.expectRevert(bytes("CentrifugeConnector/invalid-pool-or-tranche"));
        bridgedConnector.deployTranche(poolId, wrongTrancheId);
    }

    function testDeployingTrancheOnNonExistentPoolFails(
        uint64 poolId,
        uint64 wrongPoolId,
        string memory tokenName,
        string memory tokenSymbol,
        bytes16 trancheId,
        uint128 price
    ) public {
        vm.assume(poolId != wrongPoolId);

        connector.addPool(poolId);
        (uint64 actualPoolId,,) = bridgedConnector.pools(poolId);
        assertEq(uint256(actualPoolId), uint256(poolId));

        connector.addTranche(poolId, trancheId, tokenName, tokenSymbol, price);
        vm.expectRevert(bytes("CentrifugeConnector/invalid-pool-or-tranche"));
        bridgedConnector.deployTranche(wrongPoolId, trancheId);
    }

    function testUpdatingMemberWorks(uint64 poolId, bytes16 trancheId, address user, uint64 validUntil) public {
        vm.assume(validUntil >= block.timestamp);
        vm.assume(user != address(0));

        connector.addPool(poolId);
        connector.addTranche(poolId, trancheId, "Some Name", "SYMBOL", 123);
        bridgedConnector.deployTranche(poolId, trancheId);
        connector.updateMember(poolId, trancheId, user, validUntil);

        (address token_,,,,) = bridgedConnector.tranches(poolId, trancheId);
        RestrictedTokenLike token = RestrictedTokenLike(token_);
        assertTrue(token.hasMember(user));

        MemberlistLike memberlist = MemberlistLike(token.memberlist());
        assertEq(memberlist.members(user), validUntil);
    }

    function testUpdatingMemberAsNonRouterFails(uint64 poolId, bytes16 trancheId, address user, uint64 validUntil)
        public
    {
        vm.assume(validUntil <= block.timestamp);
        vm.assume(user != address(0));

        vm.expectRevert(bytes("CentrifugeConnector/not-the-gateway"));
        bridgedConnector.updateMember(poolId, trancheId, user, validUntil);
    }

    function testUpdatingMemberForNonExistentPoolFails(
        uint64 poolId,
        bytes16 trancheId,
        address user,
        uint64 validUntil
    ) public {
        vm.assume(validUntil > block.timestamp);
        bridgedConnector.file("gateway", address(this));
        vm.expectRevert(bytes("CentrifugeConnector/invalid-pool-or-tranche"));
        bridgedConnector.updateMember(poolId, trancheId, user, validUntil);
    }

    function testUpdatingMemberForNonExistentTrancheFails(
        uint64 poolId,
        bytes16 trancheId,
        address user,
        uint64 validUntil
    ) public {
        vm.assume(validUntil > block.timestamp);
        bridgedConnector.file("gateway", address(this));
        bridgedConnector.addPool(poolId);
        vm.expectRevert(bytes("CentrifugeConnector/invalid-pool-or-tranche"));
        bridgedConnector.updateMember(poolId, trancheId, user, validUntil);
    }

    function testUpdatingTokenPriceWorks(uint64 poolId, bytes16 trancheId, uint128 price) public {
        connector.addPool(poolId);
        connector.addTranche(poolId, trancheId, "Some Name", "SYMBOL", 123);
        connector.updateTokenPrice(poolId, trancheId, price);

        (, uint256 latestPrice, uint256 lastPriceUpdate,,) = bridgedConnector.tranches(poolId, trancheId);
        assertEq(latestPrice, price);
        assertEq(lastPriceUpdate, block.timestamp);
    }

    function testUpdatingTokenPriceAsNonRouterFails(uint64 poolId, bytes16 trancheId, uint128 price) public {
        connector.addPool(poolId);
        connector.addTranche(poolId, trancheId, "Some Name", "SYMBOL", 123);
        vm.expectRevert(bytes("CentrifugeConnector/not-the-gateway"));
        bridgedConnector.updateTokenPrice(poolId, trancheId, price);
    }

    function testUpdatingTokenPriceForNonExistentPoolFails(uint64 poolId, bytes16 trancheId, uint128 price) public {
        bridgedConnector.file("gateway", address(this));
        vm.expectRevert(bytes("CentrifugeConnector/invalid-pool-or-tranche"));
        bridgedConnector.updateTokenPrice(poolId, trancheId, price);
    }

    function testUpdatingTokenPriceForNonExistentTrancheFails(uint64 poolId, bytes16 trancheId, uint128 price) public {
        bridgedConnector.file("gateway", address(this));
        bridgedConnector.addPool(poolId);
        vm.expectRevert(bytes("CentrifugeConnector/invalid-pool-or-tranche"));
        bridgedConnector.updateTokenPrice(poolId, trancheId, price);
    }

    // Test transferring `amount` to the address(this)'s account (Centrifuge Chain -> EVM like) and then try
    // transferring that amount to a `centChainAddress` (EVM -> Centrifuge Chain like).
    function testTransferToCentrifuge(
        uint64 poolId,
        string memory tokenName,
        string memory tokenSymbol,
        bytes16 trancheId,
        uint128 price,
        bytes32 centChainAddress,
        uint128 amount,
        uint64 validUntil
    ) public {
        vm.assume(validUntil > block.timestamp + 7 days);
        connector.addPool(poolId);
        connector.addTranche(poolId, trancheId, tokenName, tokenSymbol, price);
        bridgedConnector.deployTranche(poolId, trancheId);
        connector.updateMember(poolId, trancheId, address(this), validUntil);

        // fund this account with amount
        connector.incomingTransfer(poolId, trancheId, address(this), 1, amount);

        // Verify the address(this) has the expected amount
        (address tokenAddress,,,,) = bridgedConnector.tranches(poolId, trancheId);
        RestrictedTokenLike token = RestrictedTokenLike(tokenAddress);
        assertEq(token.balanceOf(address(this)), amount);

        // Now send the transfer from EVM -> Cent Chain
        token.approve(address(bridgedConnector), amount);
        bridgedConnector.transferToCentrifuge(poolId, trancheId, centChainAddress, amount);
        assertEq(token.balanceOf(address(this)), 0);

        // Finally, verify the connector called `router.send`
        bytes memory message = ConnectorMessages.formatTransfer(
            poolId,
            trancheId,
            ConnectorMessages.formatDomain(ConnectorMessages.Domain.Centrifuge),
            centChainAddress,
            0,
            amount
        );
        assertEq(mockXcmRouter.sentMessages(message), true);
    }

    function testTransferFromCentrifuge(
        uint64 poolId,
        string memory tokenName,
        string memory tokenSymbol,
        bytes16 trancheId,
        uint128 price,
        address destinationAddress,
        uint128 amount,
        uint64 validUntil
    ) public {
        vm.assume(validUntil > block.timestamp + 7 days);
        connector.addPool(poolId);
        connector.addTranche(poolId, trancheId, tokenName, tokenSymbol, price);
        bridgedConnector.deployTranche(poolId, trancheId);
        connector.updateMember(poolId, trancheId, destinationAddress, validUntil);

        bytes9 encodedDomain = ConnectorMessages.formatDomain(ConnectorMessages.Domain.Centrifuge);
        connector.incomingTransfer(poolId, trancheId, destinationAddress, 1, amount);

        (address token,,,,) = bridgedConnector.tranches(poolId, trancheId);
        assertEq(ERC20Like(token).balanceOf(destinationAddress), amount);
    }

    function testTransferFromCentrifugeWithoutMemberFails(
        uint64 poolId,
        string memory tokenName,
        string memory tokenSymbol,
        bytes16 trancheId,
        uint128 price,
        uint64 destinationChainId,
        address destinationAddress,
        uint128 amount,
        uint64 validUntil
    ) public {
        vm.assume(validUntil > block.timestamp + 7 days);
        connector.addPool(poolId);
        connector.addTranche(poolId, trancheId, tokenName, tokenSymbol, price);
        bridgedConnector.deployTranche(poolId, trancheId);

        bytes9 encodedDomain = ConnectorMessages.formatDomain(ConnectorMessages.Domain.EVM, destinationChainId);
        vm.expectRevert(bytes("CentrifugeConnector/not-a-member"));
        connector.incomingTransfer(poolId, trancheId, destinationAddress, 1, amount);

        (address token,,,,) = bridgedConnector.tranches(poolId, trancheId);
        assertEq(ERC20Like(token).balanceOf(destinationAddress), 0);
    }

    function testTransferToEVM(
        uint64 poolId,
        string memory tokenName,
        string memory tokenSymbol,
        bytes16 trancheId,
        uint128 price,
        uint64 destinationChainId,
        address destinationAddress,
        uint128 amount,
        uint64 validUntil
    ) public {
        vm.assume(validUntil > block.timestamp + 7 days);
        vm.assume(destinationAddress != address(0));
        vm.assume(amount > 0);
        connector.addPool(poolId);
        connector.addTranche(poolId, trancheId, tokenName, tokenSymbol, price);
        bridgedConnector.deployTranche(poolId, trancheId);
        connector.updateMember(poolId, trancheId, destinationAddress, validUntil);
        connector.updateMember(poolId, trancheId, address(this), validUntil);

        // Fund this address with amount
        connector.incomingTransfer(poolId, trancheId, address(this), 1, amount);
        (address token,,,,) = bridgedConnector.tranches(poolId, trancheId);
        assertEq(ERC20Like(token).balanceOf(address(this)), amount);

        // Approve and transfer amont from this address to destinationAddress
        ERC20Like(token).approve(address(bridgedConnector), amount);
        bridgedConnector.transferToEVM(poolId, trancheId, destinationAddress, 2, amount);
        assertEq(ERC20Like(token).balanceOf(address(this)), 0);
    }

    // helpers
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
        while (i < 32 && _bytes32[i] != 0) {
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
