// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.18;
pragma abicoder v2;

import {CentrifugeConnector} from "src/Connector.sol";
import {ConnectorGateway} from "src/routers/Gateway.sol";
import {ConnectorEscrow} from "src/Escrow.sol";
import {TrancheTokenFactory, MemberlistFactory} from "src/token/factory.sol";
import {RestrictedTokenLike} from "src/token/restricted.sol";
import {ERC20} from "src/token/erc20.sol";
import {MemberlistLike, Memberlist} from "src/token/memberlist.sol";
import {MockHomeConnector} from "./mock/MockHomeConnector.sol";
import {MockXcmRouter} from "./mock/MockXcmRouter.sol";
import {ConnectorMessages} from "../src/Messages.sol";
import "forge-std/Test.sol";
import "../src/Connector.sol";

interface EscrowLike_ {
    function approve(address token, address spender, uint256 value) external;
    function rely(address usr) external;
}

contract ConnectorTest is Test {
    CentrifugeConnector bridgedConnector;
    ConnectorGateway gateway;
    MockHomeConnector connector;
    MockXcmRouter mockXcmRouter;

    function setUp() public {
        vm.chainId(1);
        address escrow_ = address(new ConnectorEscrow());
        address tokenFactory_ = address(new TrancheTokenFactory());
        address memberlistFactory_ = address(new MemberlistFactory());

        bridgedConnector = new CentrifugeConnector(escrow_, tokenFactory_, memberlistFactory_);

        mockXcmRouter = new MockXcmRouter(address(bridgedConnector));

        connector = new MockHomeConnector(address(mockXcmRouter));
        gateway = new ConnectorGateway(address(bridgedConnector), address(mockXcmRouter));
        bridgedConnector.file("gateway", address(gateway));
        EscrowLike_(escrow_).rely(address(bridgedConnector));
        mockXcmRouter.file("gateway", address(gateway));
    }

    function testAddCurrencyWorks(uint128 currency, uint128 badCurrency) public {
        vm.assume(currency > 0);
        vm.assume(badCurrency > 0);
        vm.assume(currency != badCurrency);

        ERC20 erc20 = newErc20("X's Dollar", "USDX", 42);
        connector.addCurrency(currency, address(erc20));
        (address address_) = bridgedConnector.currencyIdToAddress(currency);
        assertEq(address_, address(erc20));

        // Verify we can't override the same currency id another address
        ERC20 badErc20 = newErc20("BadActor's Dollar", "BADUSD", 66);
        vm.expectRevert(bytes("CentrifugeConnector/currency-already-added"));
        connector.addCurrency(currency, address(badErc20));
        assertEq(bridgedConnector.currencyIdToAddress(currency), address(erc20));

        // Verify we can't add a currency address that already exists associated with a different currency id
        vm.expectRevert(bytes("CentrifugeConnector/currency-already-added"));
        connector.addCurrency(badCurrency, address(erc20));
        assertEq(bridgedConnector.currencyIdToAddress(currency), address(erc20));
    }

    function testAddPoolWorks(uint64 poolId) public {
        connector.addPool(poolId);
        (uint64 actualPoolId,,) = bridgedConnector.pools(poolId);
        assertEq(uint256(actualPoolId), uint256(poolId));
    }

    function testAllowPoolCurrencyWorks(uint128 currency, uint64 poolId) public {
        ERC20 token = newErc20("X's Dollar", "USDX", 42);
        connector.addCurrency(currency, address(token));
        connector.addPool(poolId);

        connector.allowPoolCurrency(currency, poolId);
        assertTrue(bridgedConnector.poolCurrencies(poolId, address(token)));
    }

    function testAllowPoolCurrencyWithUnknownCurrencyFails(uint128 currency, uint64 poolId) public {
        connector.addPool(poolId);
        vm.expectRevert(bytes("CentrifugeConnector/unknown-currency"));
        connector.allowPoolCurrency(currency, poolId);
    }

    function testAddingPoolMultipleTimesFails(uint64 poolId) public {
        connector.addPool(poolId);

        vm.expectRevert(bytes("CentrifugeConnector/pool-already-added"));
        connector.addPool(poolId);
    }

    function testAddingPoolAsNonRouterFails(uint64 poolId) public {
        vm.expectRevert(bytes("CentrifugeConnector/not-the-gateway"));
        bridgedConnector.addPool(poolId);
    }

    function testAddingSingleTrancheWorks(
        uint64 poolId,
        bytes16 trancheId,
        string memory tokenName,
        string memory tokenSymbol,
        uint8 decimals,
        uint128 price
    ) public {
        connector.addPool(poolId);
        (uint64 actualPoolId,,) = bridgedConnector.pools(poolId);
        assertEq(uint256(actualPoolId), uint256(poolId));

        connector.addTranche(poolId, trancheId, tokenName, tokenSymbol, decimals, price);
        bridgedConnector.deployTranche(poolId, trancheId);

        (
            address token_,
            uint256 latestPrice,
            ,
            string memory actualTokenName,
            string memory actualTokenSymbol,
            uint8 actualDecimals
        ) = bridgedConnector.tranches(poolId, trancheId);
        assertTrue(token_ != address(0));
        assertEq(latestPrice, price);

        // Comparing raw input to output can erroneously fail when a byte string is given.
        // Intended behaviour is that byte strings will be treated as bytes and converted to strings
        // instead of treated as strings themselves. This conversion from string to bytes32 to string
        // is used to simulate this intended behaviour.
        assertEq(actualTokenName, bytes32ToString(stringToBytes32(tokenName)));
        assertEq(actualTokenSymbol, bytes32ToString(stringToBytes32(tokenSymbol)));
        assertEq(actualDecimals, decimals);

        RestrictedTokenLike token = RestrictedTokenLike(token_);
        assertEq(token.name(), bytes32ToString(stringToBytes32(tokenName)));
        assertEq(token.symbol(), bytes32ToString(stringToBytes32(tokenSymbol)));
        assertEq(token.decimals(), decimals);
    }

    function testAddingTrancheMultipleTimesFails(
        uint64 poolId,
        uint8 decimals,
        string memory tokenName,
        string memory tokenSymbol,
        bytes16 trancheId,
        uint128 price
    ) public {
        connector.addPool(poolId);
        connector.addTranche(poolId, trancheId, tokenName, tokenSymbol, decimals, price);

        vm.expectRevert(bytes("CentrifugeConnector/tranche-already-added"));
        connector.addTranche(poolId, trancheId, tokenName, tokenSymbol, decimals, price);
    }

    function testAddingMultipleTranchesWorks(
        uint64 poolId,
        bytes16[] calldata trancheIds,
        string memory tokenName,
        string memory tokenSymbol,
        uint8 decimals,
        uint128 price
    ) public {
        vm.assume(trancheIds.length > 0 && trancheIds.length < 5);
        vm.assume(!hasDuplicates(trancheIds));
        connector.addPool(poolId);

        for (uint256 i = 0; i < trancheIds.length; i++) {
            connector.addTranche(poolId, trancheIds[i], tokenName, tokenSymbol, decimals, price);
            bridgedConnector.deployTranche(poolId, trancheIds[i]);
            (address token, uint256 latestPrice,,,, uint8 actualDecimals) =
                bridgedConnector.tranches(poolId, trancheIds[i]);
            assertEq(latestPrice, price);
            assertTrue(token != address(0));
            assertEq(actualDecimals, decimals);
        }
    }

    function testAddingTranchesAsNonRouterFails(
        uint64 poolId,
        bytes16 trancheId,
        string memory tokenName,
        string memory tokenSymbol,
        uint8 decimals,
        uint128 price
    ) public {
        connector.addPool(poolId);
        vm.expectRevert(bytes("CentrifugeConnector/not-the-gateway"));
        bridgedConnector.addTranche(poolId, trancheId, tokenName, tokenSymbol, decimals, price);
    }

    function testAddingTranchesForNonExistentPoolFails(
        uint64 poolId,
        bytes16 trancheId,
        string memory tokenName,
        string memory tokenSymbol,
        uint8 decimals,
        uint128 price
    ) public {
        vm.expectRevert(bytes("CentrifugeConnector/invalid-pool"));
        connector.addTranche(poolId, trancheId, tokenName, tokenSymbol, decimals, price);
    }

    function testDeployingTrancheMultipleTimesFails(
        uint64 poolId,
        uint8 decimals,
        string memory tokenName,
        string memory tokenSymbol,
        bytes16 trancheId,
        uint128 price
    ) public {
        connector.addPool(poolId);
        connector.addTranche(poolId, trancheId, tokenName, tokenSymbol, decimals, price);
        bridgedConnector.deployTranche(poolId, trancheId);

        vm.expectRevert(bytes("CentrifugeConnector/tranche-already-deployed"));
        bridgedConnector.deployTranche(poolId, trancheId);
    }

    function testDeployingWrongTrancheFails(
        uint64 poolId,
        uint8 decimals,
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

        connector.addTranche(poolId, trancheId, tokenName, tokenSymbol, decimals, price);
        vm.expectRevert(bytes("CentrifugeConnector/invalid-pool-or-tranche"));
        bridgedConnector.deployTranche(poolId, wrongTrancheId);
    }

    function testDeployingTrancheOnNonExistentPoolFails(
        uint64 poolId,
        uint8 decimals,
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

        connector.addTranche(poolId, trancheId, tokenName, tokenSymbol, decimals, price);
        vm.expectRevert(bytes("CentrifugeConnector/invalid-pool-or-tranche"));
        bridgedConnector.deployTranche(wrongPoolId, trancheId);
    }

    function testUpdatingMemberWorks(uint64 poolId, uint8 decimals, bytes16 trancheId, address user, uint64 validUntil)
        public
    {
        vm.assume(validUntil >= block.timestamp);
        vm.assume(user != address(0));

        connector.addPool(poolId);
        connector.addTranche(poolId, trancheId, "Some Name", "SYMBOL", decimals, 123);
        bridgedConnector.deployTranche(poolId, trancheId);
        connector.updateMember(poolId, trancheId, user, validUntil);

        (address token_,,,,,) = bridgedConnector.tranches(poolId, trancheId);
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
        connector.addPool(poolId);

        vm.expectRevert(bytes("CentrifugeConnector/invalid-pool-or-tranche"));
        connector.updateMember(poolId, trancheId, user, validUntil);
    }

    function testUpdatingTokenPriceWorks(uint64 poolId, uint8 decimals, bytes16 trancheId, uint128 price) public {
        connector.addPool(poolId);
        connector.addTranche(poolId, trancheId, "Some Name", "SYMBOL", decimals, 123);
        connector.updateTokenPrice(poolId, trancheId, price);

        (, uint256 latestPrice, uint256 lastPriceUpdate,,,) = bridgedConnector.tranches(poolId, trancheId);
        assertEq(latestPrice, price);
        assertEq(lastPriceUpdate, block.timestamp);
    }

    function testUpdatingTokenPriceAsNonRouterFails(uint64 poolId, uint8 decimals, bytes16 trancheId, uint128 price)
        public
    {
        connector.addPool(poolId);
        connector.addTranche(poolId, trancheId, "Some Name", "SYMBOL", decimals, 123);
        vm.expectRevert(bytes("CentrifugeConnector/not-the-gateway"));
        bridgedConnector.updateTokenPrice(poolId, trancheId, price);
    }

    function testUpdatingTokenPriceForNonExistentPoolFails(uint64 poolId, bytes16 trancheId, uint128 price) public {
        bridgedConnector.file("gateway", address(this));
        vm.expectRevert(bytes("CentrifugeConnector/invalid-pool-or-tranche"));
        bridgedConnector.updateTokenPrice(poolId, trancheId, price);
    }

    function testUpdatingTokenPriceForNonExistentTrancheFails(uint64 poolId, bytes16 trancheId, uint128 price) public {
        connector.addPool(poolId);

        vm.expectRevert(bytes("CentrifugeConnector/invalid-pool-or-tranche"));
        connector.updateTokenPrice(poolId, trancheId, price);
    }

    function testIncomingTransferWithoutEscrowFundsFails(
        string memory tokenName,
        string memory tokenSymbol,
        uint8 decimals,
        uint128 currency,
        bytes32 sender,
        address recipient,
        uint128 amount
    ) public {
        vm.assume(decimals > 0);
        vm.assume(amount > 0);
        vm.assume(recipient != address(0));

        ERC20 erc20 = newErc20(tokenName, tokenSymbol, decimals);
        connector.addCurrency(currency, address(erc20));

        assertEq(erc20.balanceOf(address(bridgedConnector.escrow())), 0);
        vm.expectRevert(bytes("ERC20/insufficient-balance"));
        connector.incomingTransfer(currency, sender, bytes32(bytes20(recipient)), amount);
        assertEq(erc20.balanceOf(address(bridgedConnector.escrow())), 0);
        assertEq(erc20.balanceOf(recipient), 0);
    }

    function testIncomingTransferWorks(
        string memory tokenName,
        string memory tokenSymbol,
        uint8 decimals,
        uint128 currency,
        bytes32 sender,
        address recipient,
        uint128 amount
    ) public {
        vm.assume(decimals > 0);
        vm.assume(amount > 0);
        vm.assume(currency != 0);
        vm.assume(recipient != address(0));

        ERC20 erc20 = newErc20(tokenName, tokenSymbol, decimals);
        connector.addCurrency(currency, address(erc20));

        // First, an outgoing transfer must take place which has funds currency of the currency moved to
        // the escrow account, from which funds are moved from into the recipient on an incoming transfer.
        erc20.approve(address(bridgedConnector), type(uint256).max);
        erc20.mint(address(this), amount);
        bridgedConnector.transfer(address(erc20), bytes32(bytes20(recipient)), amount);
        assertEq(erc20.balanceOf(address(bridgedConnector.escrow())), amount);

        // Now we test the incoming message
        connector.incomingTransfer(currency, sender, bytes32(bytes20(recipient)), amount);
        assertEq(erc20.balanceOf(address(bridgedConnector.escrow())), 0);
        assertEq(erc20.balanceOf(recipient), amount);
    }

    // Verify that funds are moved from the msg.sender into the escrow account
    function testOutgoingTransferWorks(
        string memory tokenName,
        string memory tokenSymbol,
        uint8 decimals,
        uint128 initialBalance,
        uint128 currency,
        bytes32 recipient,
        uint128 amount
    ) public {
        vm.assume(decimals > 0);
        vm.assume(amount > 0);
        vm.assume(currency != 0);
        vm.assume(initialBalance >= amount);

        ERC20 erc20 = newErc20(tokenName, tokenSymbol, decimals);

        vm.expectRevert(bytes("CentrifugeConnector/unknown-currency"));
        bridgedConnector.transfer(address(erc20), recipient, amount);
        connector.addCurrency(currency, address(erc20));

        erc20.mint(address(this), initialBalance);
        assertEq(erc20.balanceOf(address(this)), initialBalance);
        assertEq(erc20.balanceOf(address(bridgedConnector.escrow())), 0);
        erc20.approve(address(bridgedConnector), type(uint256).max);

        bridgedConnector.transfer(address(erc20), recipient, amount);
        assertEq(erc20.balanceOf(address(this)), initialBalance - amount);
        assertEq(erc20.balanceOf(address(bridgedConnector.escrow())), amount);
    }
    // Test transferring `amount` to the address(this)'s account (Centrifuge Chain -> EVM like) and then try
    // transferring that amount to a `centChainAddress` (EVM -> Centrifuge Chain like).

    function testTransferTrancheTokensToCentrifuge(
        uint64 poolId,
        uint8 decimals,
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
        connector.addTranche(poolId, trancheId, tokenName, tokenSymbol, decimals, price);
        bridgedConnector.deployTranche(poolId, trancheId);
        connector.updateMember(poolId, trancheId, address(this), validUntil);

        // fund this account with amount
        connector.incomingTransferTrancheTokens(poolId, trancheId, uint64(block.chainid), address(this), amount);

        // Verify the address(this) has the expected amount
        (address tokenAddress,,,,,) = bridgedConnector.tranches(poolId, trancheId);
        RestrictedTokenLike token = RestrictedTokenLike(tokenAddress);
        assertEq(token.balanceOf(address(this)), amount);

        // Now send the transfer from EVM -> Cent Chain
        token.approve(address(bridgedConnector), amount);
        bridgedConnector.transferTrancheTokensToCentrifuge(poolId, trancheId, centChainAddress, amount);
        assertEq(token.balanceOf(address(this)), 0);

        // Finally, verify the connector called `router.send`
        bytes memory message = ConnectorMessages.formatTransferTrancheTokens(
            poolId,
            trancheId,
            bytes32(bytes20(address(this))),
            ConnectorMessages.formatDomain(ConnectorMessages.Domain.Centrifuge),
            centChainAddress,
            amount
        );
        assertEq(mockXcmRouter.sentMessages(message), true);
    }

    function testTransferTrancheTokensFromCentrifuge(
        uint64 poolId,
        bytes16 trancheId,
        string memory tokenName,
        string memory tokenSymbol,
        uint8 decimals,
        uint128 price,
        uint64 validUntil,
        address destinationAddress,
        uint128 amount
    ) public {
        vm.assume(validUntil > block.timestamp + 7 days);
        vm.assume(destinationAddress != address(0));
        
        connector.addPool(poolId);
        connector.addTranche(poolId, trancheId, tokenName, tokenSymbol, decimals, price);
        bridgedConnector.deployTranche(poolId, trancheId);
        connector.updateMember(poolId, trancheId, destinationAddress, validUntil);

        connector.incomingTransferTrancheTokens(poolId, trancheId, uint64(block.chainid), destinationAddress, amount);
        (address token,,,,,) = bridgedConnector.tranches(poolId, trancheId);
        assertEq(ERC20Like(token).balanceOf(destinationAddress), amount);
    }

    function testTransferTrancheTokensFromCentrifugeWithoutMemberFails(
        uint64 poolId,
        bytes16 trancheId,
        string memory tokenName,
        string memory tokenSymbol,
        uint8 decimals,
        uint128 price,
        address destinationAddress,
        uint128 amount
    ) public {
        vm.assume(destinationAddress != address(0));
        connector.addPool(poolId);
        connector.addTranche(poolId, trancheId, tokenName, tokenSymbol, decimals, price);
        bridgedConnector.deployTranche(poolId, trancheId);

        vm.expectRevert(bytes("CentrifugeConnector/not-a-member"));
        connector.incomingTransferTrancheTokens(poolId, trancheId, uint64(block.chainid), destinationAddress, amount);

        (address token,,,,,) = bridgedConnector.tranches(poolId, trancheId);
        assertEq(ERC20Like(token).balanceOf(destinationAddress), 0);
    }

    function testTransferTrancheTokensToEVM(
        uint64 poolId,
        bytes16 trancheId,
        string memory tokenName,
        string memory tokenSymbol,
        uint8 decimals,
        uint128 price,
        uint64 validUntil,
        address destinationAddress,
        uint128 amount
    ) public {
        vm.assume(validUntil > block.timestamp + 7 days);
        vm.assume(destinationAddress != address(0));
        vm.assume(amount > 0);
        connector.addPool(poolId);
        connector.addTranche(poolId, trancheId, tokenName, tokenSymbol, decimals, price);
        bridgedConnector.deployTranche(poolId, trancheId);
        connector.updateMember(poolId, trancheId, destinationAddress, validUntil);
        connector.updateMember(poolId, trancheId, address(this), validUntil);

        // Fund this address with amount
        connector.incomingTransferTrancheTokens(poolId, trancheId, uint64(block.chainid), address(this), amount);
        (address token,,,,,) = bridgedConnector.tranches(poolId, trancheId);
        assertEq(ERC20Like(token).balanceOf(address(this)), amount);

        // Approve and transfer amount from this address to destinationAddress
        ERC20Like(token).approve(address(bridgedConnector), amount);
        bridgedConnector.transferTrancheTokensToEVM(
            poolId, trancheId, uint64(block.chainid), destinationAddress, amount
        );
        assertEq(ERC20Like(token).balanceOf(address(this)), 0);
    }

    function testIncreaseInvestOrder(
        uint64 poolId,
        bytes16 trancheId,
        string memory trancheTokenName,
        string memory trancheTokenSymbol,
        uint8 trancheDecimals,
        uint128 price,
        uint64 validUntil,
        uint128 currency,
        uint8 erc20Decimals,
        uint128 amount
    ) public {
        vm.assume(amount > 0);
        vm.assume(trancheDecimals & erc20Decimals > 0);
        vm.assume(validUntil > block.timestamp + 7 days);
        vm.assume(currency != 0);

        ERC20 erc20 = newErc20("X's Dollar", "USDX", erc20Decimals);

        vm.expectRevert(bytes("CentrifugeConnector/unknown-tranche-token"));
        bridgedConnector.increaseInvestOrder(poolId, trancheId, address(erc20), amount);
        connector.addPool(poolId);
        connector.addTranche(poolId, trancheId, trancheTokenName, trancheTokenSymbol, trancheDecimals, price);
        bridgedConnector.deployTranche(poolId, trancheId);

        vm.expectRevert(bytes("CentrifugeConnector/not-a-member"));
        bridgedConnector.increaseInvestOrder(poolId, trancheId, address(erc20), amount);
        connector.updateMember(poolId, trancheId, address(this), validUntil);

        vm.expectRevert(bytes("CentrifugeConnector/unknown-currency"));
        bridgedConnector.increaseInvestOrder(poolId, trancheId, address(erc20), amount);
        connector.addCurrency(currency, address(erc20));

        vm.expectRevert(bytes("CentrifugeConnector/pool-currency-not-allowed"));
        bridgedConnector.increaseInvestOrder(poolId, trancheId, address(erc20), amount);
        connector.allowPoolCurrency(currency, poolId);

        erc20.approve(address(bridgedConnector), type(uint256).max);
        erc20.mint(address(this), amount);
        assertEq(erc20.balanceOf(address(bridgedConnector.escrow())), 0);
        bridgedConnector.increaseInvestOrder(poolId, trancheId, address(erc20), amount);
        assertEq(erc20.balanceOf(address(bridgedConnector.escrow())), amount);
        assertEq(erc20.balanceOf(address(this)), 0);
    }

    function testDecreaseInvestOrder(
        uint64 poolId,
        bytes16 trancheId,
        string memory trancheTokenName,
        string memory trancheTokenSymbol,
        uint8 trancheDecimals,
        uint128 price,
        uint64 validUntil,
        uint128 currency,
        uint8 erc20Decimals,
        uint128 amount
    ) public {
        vm.assume(amount > 0);
        vm.assume(trancheDecimals & erc20Decimals > 0);
        vm.assume(validUntil > block.timestamp + 7 days);
        vm.assume(currency != 0);

        ERC20 erc20 = newErc20("X's Dollar", "USDX", erc20Decimals);

        vm.expectRevert(bytes("CentrifugeConnector/unknown-tranche-token"));
        bridgedConnector.decreaseInvestOrder(poolId, trancheId, address(erc20), amount);
        connector.addPool(poolId);
        connector.addTranche(poolId, trancheId, trancheTokenName, trancheTokenSymbol, trancheDecimals, price);
        bridgedConnector.deployTranche(poolId, trancheId);

        vm.expectRevert(bytes("CentrifugeConnector/not-a-member"));
        bridgedConnector.decreaseInvestOrder(poolId, trancheId, address(erc20), amount);
        connector.updateMember(poolId, trancheId, address(this), validUntil);

        vm.expectRevert(bytes("CentrifugeConnector/unknown-currency"));
        bridgedConnector.decreaseInvestOrder(poolId, trancheId, address(erc20), amount);
        connector.addCurrency(currency, address(erc20));

        vm.expectRevert(bytes("CentrifugeConnector/pool-currency-not-allowed"));
        bridgedConnector.decreaseInvestOrder(poolId, trancheId, address(erc20), amount);
        connector.allowPoolCurrency(currency, poolId);

        assertEq(erc20.balanceOf(address(bridgedConnector.escrow())), 0);
        assertEq(erc20.balanceOf(address(this)), 0);
        bridgedConnector.decreaseInvestOrder(poolId, trancheId, address(erc20), amount);
        assertEq(erc20.balanceOf(address(bridgedConnector.escrow())), 0);
        assertEq(erc20.balanceOf(address(this)), 0);
    }

    function testIncreaseRedeemOrder(
        uint64 poolId,
        bytes16 trancheId,
        string memory trancheTokenName,
        string memory trancheTokenSymbol,
        uint8 trancheDecimals,
        uint128 price,
        uint64 validUntil,
        uint128 currency,
        uint8 erc20Decimals,
        uint128 amount
    ) public {
        vm.assume(amount > 0);
        vm.assume(trancheDecimals & erc20Decimals > 0);
        vm.assume(validUntil > block.timestamp + 7 days);
        vm.assume(currency != 0);

        ERC20 erc20 = newErc20("X's Dollar", "USDX", erc20Decimals);

        vm.expectRevert(bytes("CentrifugeConnector/unknown-tranche-token"));
        bridgedConnector.increaseRedeemOrder(poolId, trancheId, address(erc20), amount);
        connector.addPool(poolId);
        connector.addTranche(poolId, trancheId, trancheTokenName, trancheTokenSymbol, trancheDecimals, price);
        bridgedConnector.deployTranche(poolId, trancheId);

        vm.expectRevert(bytes("CentrifugeConnector/not-a-member"));
        bridgedConnector.increaseRedeemOrder(poolId, trancheId, address(erc20), amount);
        connector.updateMember(poolId, trancheId, address(this), validUntil);

        vm.expectRevert(bytes("CentrifugeConnector/unknown-currency"));
        bridgedConnector.increaseRedeemOrder(poolId, trancheId, address(erc20), amount);
        connector.addCurrency(currency, address(erc20));

        vm.expectRevert(bytes("CentrifugeConnector/pool-currency-not-allowed"));
        bridgedConnector.increaseRedeemOrder(poolId, trancheId, address(erc20), amount);
        connector.allowPoolCurrency(currency, poolId);

        assertEq(erc20.balanceOf(address(bridgedConnector.escrow())), 0);
        assertEq(erc20.balanceOf(address(this)), 0);
        bridgedConnector.increaseRedeemOrder(poolId, trancheId, address(erc20), amount);
        assertEq(erc20.balanceOf(address(bridgedConnector.escrow())), 0);
        assertEq(erc20.balanceOf(address(this)), 0);
    }

    function testDecreaseRedeemOrder(
        uint64 poolId,
        bytes16 trancheId,
        string memory trancheTokenName,
        string memory trancheTokenSymbol,
        uint8 trancheDecimals,
        uint128 price,
        uint64 validUntil,
        uint128 currency,
        uint8 erc20Decimals,
        uint128 amount
    ) public {
        vm.assume(amount > 0);
        vm.assume(trancheDecimals & erc20Decimals > 0);
        vm.assume(validUntil > block.timestamp + 7 days);
        vm.assume(currency != 0);

        ERC20 erc20 = newErc20("X's Dollar", "USDX", erc20Decimals);

        vm.expectRevert(bytes("CentrifugeConnector/unknown-tranche-token"));
        bridgedConnector.decreaseRedeemOrder(poolId, trancheId, address(erc20), amount);
        connector.addPool(poolId);
        connector.addTranche(poolId, trancheId, trancheTokenName, trancheTokenSymbol, trancheDecimals, price);
        bridgedConnector.deployTranche(poolId, trancheId);

        vm.expectRevert(bytes("CentrifugeConnector/not-a-member"));
        bridgedConnector.decreaseRedeemOrder(poolId, trancheId, address(erc20), amount);
        connector.updateMember(poolId, trancheId, address(this), validUntil);

        vm.expectRevert(bytes("CentrifugeConnector/unknown-currency"));
        bridgedConnector.decreaseRedeemOrder(poolId, trancheId, address(erc20), amount);
        connector.addCurrency(currency, address(erc20));

        vm.expectRevert(bytes("CentrifugeConnector/pool-currency-not-allowed"));
        bridgedConnector.decreaseRedeemOrder(poolId, trancheId, address(erc20), amount);
        connector.allowPoolCurrency(currency, poolId);

        assertEq(erc20.balanceOf(address(bridgedConnector.escrow())), 0);
        assertEq(erc20.balanceOf(address(this)), 0);
        bridgedConnector.decreaseRedeemOrder(poolId, trancheId, address(erc20), amount);
        assertEq(erc20.balanceOf(address(bridgedConnector.escrow())), 0);
        assertEq(erc20.balanceOf(address(this)), 0);
    }

    function testCollectRedeem(
        uint64 poolId,
        bytes16 trancheId,
        string memory trancheTokenName,
        string memory trancheTokenSymbol,
        uint8 trancheDecimals,
        uint128 price,
        uint64 validUntil,
        uint128 amount
    ) public {
        vm.assume(amount > 0);
        vm.assume(trancheDecimals > 0);
        vm.assume(validUntil > block.timestamp + 7 days);

        vm.expectRevert(bytes("CentrifugeConnector/unknown-tranche-token"));
        bridgedConnector.collectRedeem(poolId, trancheId);
        connector.addPool(poolId);
        connector.addTranche(poolId, trancheId, trancheTokenName, trancheTokenSymbol, trancheDecimals, price);
        bridgedConnector.deployTranche(poolId, trancheId);

        vm.expectRevert(bytes("CentrifugeConnector/not-a-member"));
        bridgedConnector.collectRedeem(poolId, trancheId);
        connector.updateMember(poolId, trancheId, address(this), validUntil);

        bridgedConnector.collectRedeem(poolId, trancheId);
    }

    function testCollectInvest(
        uint64 poolId,
        bytes16 trancheId,
        string memory trancheTokenName,
        string memory trancheTokenSymbol,
        uint8 trancheDecimals,
        uint128 price,
        uint64 validUntil,
        uint128 amount
    ) public {
        vm.assume(amount > 0);
        vm.assume(trancheDecimals > 0);
        vm.assume(validUntil > block.timestamp + 7 days);

        vm.expectRevert(bytes("CentrifugeConnector/unknown-tranche-token"));
        bridgedConnector.collectInvest(poolId, trancheId);
        connector.addPool(poolId);
        connector.addTranche(poolId, trancheId, trancheTokenName, trancheTokenSymbol, trancheDecimals, price);
        bridgedConnector.deployTranche(poolId, trancheId);

        vm.expectRevert(bytes("CentrifugeConnector/not-a-member"));
        bridgedConnector.collectInvest(poolId, trancheId);
        connector.updateMember(poolId, trancheId, address(this), validUntil);

        bridgedConnector.collectInvest(poolId, trancheId);
    }

    // helpers
    function newErc20(string memory name, string memory symbol, uint8 decimals) internal returns (ERC20) {
        ERC20 erc20 = new ERC20(decimals);
        erc20.file("name", name);
        erc20.file("symbol", symbol);

        return erc20;
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

    function hasDuplicates(bytes16[] calldata array) internal pure returns (bool) {
        uint256 length = array.length;
        for (uint256 i = 0; i < length; i++) {
            for (uint256 j = i + 1; j < length; j++) {
                if (array[i] == array[j]) {
                    return true;
                }
            }
        }
        return false;
    }
}
