// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import "test/BaseTest.sol";
import "test/mocks/RestrictionManagerFactory.sol";
import {CastLib} from "src/libraries/CastLib.sol";

contract PoolManagerTest is BaseTest {
    using CastLib for *;

    // Deployment
    function testDeployment(address nonWard) public {
        vm.assume(nonWard != address(root) && nonWard != address(gateway) && nonWard != address(this));

        // values set correctly
        assertEq(address(poolManager.gateway()), address(gateway));
        assertEq(address(poolManager.escrow()), address(escrow));
        assertEq(address(poolManager.investmentManager()), address(investmentManager));
        assertEq(address(gateway.poolManager()), address(poolManager));
        assertEq(address(investmentManager.poolManager()), address(poolManager));

        // permissions set correctly
        assertEq(poolManager.wards(address(root)), 1);
        assertEq(poolManager.wards(address(gateway)), 1);
        assertEq(escrow.wards(address(poolManager)), 1);
        assertEq(poolManager.wards(nonWard), 0);
    }

    function testFile() public {
        address newGateway = makeAddr("newGateway");
        poolManager.file("gateway", newGateway);
        assertEq(address(poolManager.gateway()), newGateway);

        address newInvestmentManager = makeAddr("newInvestmentManager");
        poolManager.file("investmentManager", newInvestmentManager);
        assertEq(address(poolManager.investmentManager()), newInvestmentManager);

        address newTrancheTokenFactory = makeAddr("newTrancheTokenFactory");
        poolManager.file("trancheTokenFactory", newTrancheTokenFactory);
        assertEq(address(poolManager.trancheTokenFactory()), newTrancheTokenFactory);

        address newRestrictionManagerFactory = makeAddr("newRestrictionManagerFactory");
        poolManager.file("restrictionManagerFactory", newRestrictionManagerFactory);
        assertEq(address(poolManager.restrictionManagerFactory()), newRestrictionManagerFactory);

        address newLiquidityPoolFactory = makeAddr("newLiquidityPoolFactory");
        poolManager.file("liquidityPoolFactory", newLiquidityPoolFactory);
        assertEq(address(poolManager.liquidityPoolFactory()), newLiquidityPoolFactory);

        address newEscrow = makeAddr("newEscrow");
        vm.expectRevert("PoolManager/file-unrecognized-param");
        poolManager.file("escrow", newEscrow);
    }

    function testAddPool(uint64 poolId) public {
        centrifugeChain.addPool(poolId);
        (uint256 createdAt) = poolManager.pools(poolId);
        assertEq(createdAt, block.timestamp);

        vm.expectRevert(bytes("PoolManager/pool-already-added"));
        centrifugeChain.addPool(poolId);

        vm.expectRevert(bytes("Auth/not-authorized"));
        vm.prank(randomUser);
        poolManager.addPool(poolId);
    }

    function testAddTranche(
        uint64 poolId,
        bytes16 trancheId,
        string memory tokenName,
        string memory tokenSymbol,
        uint8 decimals,
        uint8 restrictionSet
    ) public {
        decimals = uint8(bound(decimals, 1, 18));
        vm.assume(bytes(tokenName).length <= 128);
        vm.assume(bytes(tokenSymbol).length <= 32);

        vm.expectRevert(bytes("PoolManager/invalid-pool"));
        centrifugeChain.addTranche(poolId, trancheId, tokenName, tokenSymbol, decimals, restrictionSet);
        centrifugeChain.addPool(poolId);

        vm.expectRevert(bytes("Auth/not-authorized"));
        vm.prank(randomUser);
        poolManager.addTranche(poolId, trancheId, tokenName, tokenSymbol, decimals, restrictionSet);

        vm.expectRevert(bytes("PoolManager/too-few-tranche-token-decimals"));
        centrifugeChain.addTranche(poolId, trancheId, tokenName, tokenSymbol, 0, restrictionSet);

        vm.expectRevert(bytes("PoolManager/too-many-tranche-token-decimals"));
        centrifugeChain.addTranche(poolId, trancheId, tokenName, tokenSymbol, 19, restrictionSet);

        centrifugeChain.addTranche(poolId, trancheId, tokenName, tokenSymbol, decimals, restrictionSet);

        vm.expectRevert(bytes("PoolManager/tranche-already-exists"));
        centrifugeChain.addTranche(poolId, trancheId, tokenName, tokenSymbol, decimals, restrictionSet);

        (,,, uint8 _restrictionSet) = poolManager.undeployedTranches(poolId, trancheId);
        assertEq(_restrictionSet, restrictionSet);

        poolManager.deployTranche(poolId, trancheId);

        TrancheToken trancheToken = TrancheToken(poolManager.getTrancheToken(poolId, trancheId));

        assertEq(tokenName, trancheToken.name());
        assertEq(tokenSymbol, trancheToken.symbol());
        assertEq(decimals, trancheToken.decimals());

        vm.expectRevert(bytes("PoolManager/tranche-already-deployed"));
        centrifugeChain.addTranche(poolId, trancheId, tokenName, tokenSymbol, decimals, restrictionSet);
    }

    function testAddMultipleTranchesWorks(
        uint64 poolId,
        bytes16[4] calldata trancheIds,
        string memory tokenName,
        string memory tokenSymbol,
        uint8 decimals,
        uint8 restrictionSet
    ) public {
        decimals = uint8(bound(decimals, 1, 18));
        vm.assume(!hasDuplicates(trancheIds));
        vm.assume(bytes(tokenName).length <= 128);
        vm.assume(bytes(tokenSymbol).length <= 32);

        centrifugeChain.addPool(poolId);

        for (uint256 i = 0; i < trancheIds.length; i++) {
            centrifugeChain.addTranche(poolId, trancheIds[i], tokenName, tokenSymbol, decimals, restrictionSet);
            poolManager.deployTranche(poolId, trancheIds[i]);
            TrancheToken trancheToken = TrancheToken(poolManager.getTrancheToken(poolId, trancheIds[i]));
            assertEq(tokenName, trancheToken.name());
            assertEq(tokenSymbol, trancheToken.symbol());
            assertEq(decimals, trancheToken.decimals());
        }
    }

    function testDeployTranche(
        uint64 poolId,
        uint8 decimals,
        uint8 restrictionSet,
        string memory tokenName,
        string memory tokenSymbol,
        bytes16 trancheId,
        uint128 currency
    ) public {
        vm.assume(currency > 0);
        decimals = uint8(bound(decimals, 1, 18));
        vm.assume(bytes(tokenName).length <= 128);
        vm.assume(bytes(tokenSymbol).length <= 32);

        centrifugeChain.addPool(poolId); // add pool

        vm.expectRevert(bytes("PoolManager/tranche-not-added"));
        poolManager.deployTranche(poolId, trancheId);
        centrifugeChain.addTranche(poolId, trancheId, tokenName, tokenSymbol, decimals, restrictionSet); // add tranche
        address trancheToken_ = poolManager.deployTranche(poolId, trancheId);
        TrancheToken trancheToken = TrancheToken(trancheToken_);
        assertEq(trancheToken.wards(address(root)), 1);
        assertEq(trancheToken.wards(address(investmentManager)), 1);
        assertEq(tokenName, trancheToken.name());
        assertEq(tokenSymbol, trancheToken.symbol());
    }

    function testRestrictionSetIntegration(uint64 poolId, bytes16 trancheId, uint8 restrictionSet) public {
        RestrictionManagerFactoryMock restrictionManagerFactory = new RestrictionManagerFactoryMock();
        poolManager.file("restrictionManagerFactory", address(restrictionManagerFactory));
        centrifugeChain.addPool(poolId);
        centrifugeChain.addTranche(poolId, trancheId, "", "", defaultDecimals, restrictionSet);
        poolManager.deployTranche(poolId, trancheId);
        // assert restrictionSet info is passed correctly to the factory
        assertEq(restrictionManagerFactory.values_uint8("restrictionSet"), restrictionSet);
    }

    function testAddCurrency(uint128 currency) public {
        uint128 badCurrency = 2;
        vm.assume(currency > 0);
        vm.assume(currency != badCurrency);
        ERC20 erc20_invalid_too_few = _newErc20("X's Dollar", "USDX", 0);
        ERC20 erc20_invalid_too_many = _newErc20("X's Dollar", "USDX", 42);

        vm.expectRevert(bytes("PoolManager/too-few-currency-decimals"));
        centrifugeChain.addCurrency(currency, address(erc20_invalid_too_few));

        vm.expectRevert(bytes("PoolManager/too-many-currency-decimals"));
        centrifugeChain.addCurrency(currency, address(erc20_invalid_too_many));

        vm.expectRevert(bytes("PoolManager/currency-id-has-to-be-greater-than-0"));
        centrifugeChain.addCurrency(0, address(erc20));

        centrifugeChain.addCurrency(currency, address(erc20));

        // Verify we can't override the same currency id another address
        vm.expectRevert(bytes("PoolManager/currency-id-in-use"));
        centrifugeChain.addCurrency(currency, makeAddr("randomCurrency"));

        // Verify we can't add a currency address that already exists associated with a different currency id
        vm.expectRevert(bytes("PoolManager/currency-address-in-use"));
        centrifugeChain.addCurrency(badCurrency, address(erc20));

        assertEq(poolManager.currencyIdToAddress(currency), address(erc20));
    }

    function testDeployLiquidityPool(
        uint64 poolId,
        uint8 decimals,
        uint8 restrictionSet,
        string memory tokenName,
        string memory tokenSymbol,
        bytes16 trancheId,
        uint128 currency
    ) public {
        decimals = uint8(bound(decimals, 1, 18));
        vm.assume(currency > 0);
        vm.assume(bytes(tokenName).length <= 128);
        vm.assume(bytes(tokenSymbol).length <= 32);

        centrifugeChain.addPool(poolId); // add pool
        centrifugeChain.addTranche(poolId, trancheId, tokenName, tokenSymbol, decimals, restrictionSet); // add tranche
        centrifugeChain.addCurrency(currency, address(erc20));

        vm.expectRevert(bytes("PoolManager/tranche-does-not-exist"));
        poolManager.deployLiquidityPool(poolId, trancheId, address(erc20));
        address trancheToken_ = poolManager.deployTranche(poolId, trancheId);

        vm.expectRevert(bytes("PoolManager/currency-not-supported"));
        poolManager.deployLiquidityPool(poolId, trancheId, address(erc20));
        centrifugeChain.allowInvestmentCurrency(poolId, currency);

        address lPoolAddress = poolManager.deployLiquidityPool(poolId, trancheId, address(erc20));
        address lPool_ = poolManager.getLiquidityPool(poolId, trancheId, address(erc20)); // make sure the pool was
            // stored in LP

        vm.expectRevert(bytes("PoolManager/liquidity-pool-already-deployed"));
        poolManager.deployLiquidityPool(poolId, trancheId, address(erc20));

        // make sure the pool was added to the tranche struct
        assertEq(lPoolAddress, lPool_);

        // check LiquidityPool state
        LiquidityPool lPool = LiquidityPool(lPool_);
        TrancheToken trancheToken = TrancheToken(trancheToken_);
        assertEq(address(lPool.manager()), address(investmentManager));
        assertEq(lPool.asset(), address(erc20));
        assertEq(lPool.poolId(), poolId);
        assertEq(lPool.trancheId(), trancheId);
        assertEq(address(lPool.share()), trancheToken_);
        assertTrue(lPool.wards(address(investmentManager)) == 1);
        assertTrue(lPool.wards(address(this)) == 0);
        assertTrue(investmentManager.wards(lPoolAddress) == 1);

        assertEq(trancheToken.name(), tokenName);
        assertEq(trancheToken.symbol(), tokenSymbol);
        assertEq(trancheToken.decimals(), decimals);
        (, uint64 actualValidUntil) = RestrictionManagerLike(address(trancheToken.restrictionManager())).restrictions(
            address(investmentManager.escrow())
        );
        assertTrue(actualValidUntil >= block.timestamp);

        assertTrue(trancheToken.wards(address(poolManager)) == 1);
        assertTrue(trancheToken.wards(lPool_) == 1);
        assertTrue(trancheToken.wards(address(this)) == 0);
        assertTrue(trancheToken.isTrustedForwarder(lPool_)); // Lpool is not trusted forwarder on token
    }

    function testIncomingTransfer(uint128 amount) public {
        vm.assume(amount > 0);
        uint128 currency = defaultCurrencyId;
        address recipient = makeAddr("recipient");
        bytes32 sender = makeAddr("sender").toBytes32();

        vm.expectRevert(bytes("PoolManager/unknown-currency"));
        centrifugeChain.incomingTransfer(currency, sender, bytes32(bytes20(recipient)), amount);
        centrifugeChain.addCurrency(currency, address(erc20));

        vm.expectRevert(bytes("SafeTransferLib/safe-transfer-from-failed"));
        centrifugeChain.incomingTransfer(currency, sender, bytes32(bytes20(recipient)), amount);

        vm.expectRevert(bytes("SafeTransferLib/safe-transfer-from-failed"));
        centrifugeChain.incomingTransfer(currency, sender, bytes32(bytes20(recipient)), amount);

        erc20.mint(address(poolManager.escrow()), amount); // fund escrow

        // Now we test the incoming message
        centrifugeChain.incomingTransfer(currency, sender, bytes32(bytes20(recipient)), amount);
        assertEq(erc20.balanceOf(address(poolManager.escrow())), 0);
        assertEq(erc20.balanceOf(recipient), amount);
    }

    // Verify that funds are moved from the msg.sender into the escrow account
    function testOutgoingTransfer(uint128 initialBalance, uint128 amount) public {
        initialBalance = uint128(bound(initialBalance, amount, type(uint128).max)); // initialBalance >= amount
        vm.assume(amount > 0);
        uint128 currency = defaultCurrencyId;
        bytes32 recipient = makeAddr("recipient").toBytes32();

        erc20.mint(address(this), initialBalance);
        assertEq(erc20.balanceOf(address(this)), initialBalance);
        assertEq(erc20.balanceOf(address(poolManager.escrow())), 0);
        erc20.approve(address(poolManager), type(uint256).max);

        vm.expectRevert(bytes("PoolManager/unknown-currency"));
        poolManager.transfer(address(erc20), recipient, amount);
        centrifugeChain.addCurrency(currency, address(erc20));

        poolManager.transfer(address(erc20), recipient, amount);
        assertEq(erc20.balanceOf(address(this)), initialBalance - amount);
        assertEq(erc20.balanceOf(address(poolManager.escrow())), amount);
    }

    function testTransferTrancheTokensToCentrifuge(uint128 amount) public {
        vm.assume(amount > 0);
        uint64 validUntil = uint64(block.timestamp + 7 days);
        bytes32 centChainAddress = makeAddr("centChainAddress").toBytes32();
        address lPool_ = deploySimplePool();
        LiquidityPool lPool = LiquidityPool(lPool_);
        TrancheTokenLike trancheToken = TrancheTokenLike(address(LiquidityPool(lPool_).share()));

        // fund this account with amount
        centrifugeChain.updateMember(lPool.poolId(), lPool.trancheId(), address(this), validUntil);
        centrifugeChain.incomingTransferTrancheTokens(
            lPool.poolId(), lPool.trancheId(), uint64(block.chainid), address(this), amount
        );
        assertEq(trancheToken.balanceOf(address(this)), amount); // Verify the address(this) has the expected amount

        // fails for invalid tranche token
        uint64 poolId = lPool.poolId();
        bytes16 trancheId = lPool.trancheId();
        vm.expectRevert(bytes("PoolManager/unknown-token"));
        poolManager.transferTrancheTokensToCentrifuge(poolId + 1, trancheId, centChainAddress, amount);

        // send the transfer from EVM -> Cent Chain
        trancheToken.approve(address(poolManager), amount);
        poolManager.transferTrancheTokensToCentrifuge(poolId, trancheId, centChainAddress, amount);
        assertEq(trancheToken.balanceOf(address(this)), 0);

        // Finally, verify the connector called `router.send`
        bytes memory message = abi.encodePacked(
            uint8(MessagesLib.Call.TransferTrancheTokens),
            poolId,
            trancheId,
            bytes32(bytes20(address(this))),
            MessagesLib.formatDomain(MessagesLib.Domain.Centrifuge),
            centChainAddress,
            amount
        );
        assertEq(router1.sent(message), 1);
    }

    function testTransferTrancheTokensFromCentrifuge(uint128 amount) public {
        vm.assume(amount > 0);
        uint64 validUntil = uint64(block.timestamp + 7 days);
        address destinationAddress = makeAddr("destinationAddress");
        address lPool_ = deploySimplePool();
        LiquidityPool lPool = LiquidityPool(lPool_);
        uint64 poolId = lPool.poolId();
        bytes16 trancheId = lPool.trancheId();

        TrancheTokenLike trancheToken = TrancheTokenLike(address(lPool.share()));

        vm.expectRevert(bytes("RestrictionManager/destination-not-a-member"));
        centrifugeChain.incomingTransferTrancheTokens(
            poolId, trancheId, uint64(block.chainid), destinationAddress, amount
        );
        centrifugeChain.updateMember(poolId, trancheId, destinationAddress, validUntil);

        vm.expectRevert(bytes("PoolManager/unknown-token"));
        centrifugeChain.incomingTransferTrancheTokens(
            poolId + 1, trancheId, uint64(block.chainid), destinationAddress, amount
        );

        assertTrue(trancheToken.checkTransferRestriction(address(0), destinationAddress, 0));
        centrifugeChain.incomingTransferTrancheTokens(
            poolId, trancheId, uint64(block.chainid), destinationAddress, amount
        );
        assertEq(trancheToken.balanceOf(destinationAddress), amount);
    }

    function testTransferTrancheTokensToEVM(uint128 amount) public {
        uint64 validUntil = uint64(block.timestamp + 7 days);
        address destinationAddress = makeAddr("destinationAddress");
        vm.assume(amount > 0);

        address lPool_ = deploySimplePool();
        LiquidityPool lPool = LiquidityPool(lPool_);
        TrancheTokenLike trancheToken = TrancheTokenLike(address(LiquidityPool(lPool_).share()));

        centrifugeChain.updateMember(lPool.poolId(), lPool.trancheId(), destinationAddress, validUntil);
        centrifugeChain.updateMember(lPool.poolId(), lPool.trancheId(), address(this), validUntil);
        assertTrue(trancheToken.checkTransferRestriction(address(0), address(this), 0));
        assertTrue(trancheToken.checkTransferRestriction(address(0), destinationAddress, 0));

        // Fund this address with samount
        centrifugeChain.incomingTransferTrancheTokens(
            lPool.poolId(), lPool.trancheId(), uint64(block.chainid), address(this), amount
        );
        assertEq(trancheToken.balanceOf(address(this)), amount);

        // fails for invalid tranche token
        uint64 poolId = lPool.poolId();
        bytes16 trancheId = lPool.trancheId();
        vm.expectRevert(bytes("PoolManager/unknown-token"));
        poolManager.transferTrancheTokensToEVM(poolId + 1, trancheId, uint64(block.chainid), destinationAddress, amount);

        // Approve and transfer amount from this address to destinationAddress
        trancheToken.approve(address(poolManager), amount);
        poolManager.transferTrancheTokensToEVM(
            lPool.poolId(), lPool.trancheId(), uint64(block.chainid), destinationAddress, amount
        );
        assertEq(trancheToken.balanceOf(address(this)), 0);
    }

    function testUpdateMember(uint64 validUntil) public {
        validUntil = uint64(bound(validUntil, block.timestamp, type(uint64).max));
        address lPool_ = deploySimplePool();
        LiquidityPool lPool = LiquidityPool(lPool_);
        TrancheTokenLike trancheToken = TrancheTokenLike(address(LiquidityPool(lPool_).share()));

        uint64 poolId = lPool.poolId();
        bytes16 trancheId = lPool.trancheId();
        vm.expectRevert(bytes("Auth/not-authorized"));
        vm.prank(randomUser);
        poolManager.updateMember(poolId, trancheId, randomUser, validUntil);

        vm.expectRevert(bytes("PoolManager/unknown-token"));
        centrifugeChain.updateMember(100, bytes16(bytes("100")), randomUser, validUntil); // use random poolId &
            // trancheId

        centrifugeChain.updateMember(poolId, trancheId, randomUser, validUntil);
        assertTrue(trancheToken.checkTransferRestriction(address(0), randomUser, 0));

        vm.expectRevert(bytes("PoolManager/escrow-member-cannot-be-updated"));
        centrifugeChain.updateMember(poolId, trancheId, address(escrow), validUntil);
    }

    function testFreezeAndUnfreeze() public {
        address lPool_ = deploySimplePool();
        LiquidityPool lPool = LiquidityPool(lPool_);
        uint64 poolId = lPool.poolId();
        bytes16 trancheId = lPool.trancheId();
        TrancheTokenLike trancheToken = TrancheTokenLike(address(LiquidityPool(lPool_).share()));
        uint64 validUntil = uint64(block.timestamp + 7 days);
        address secondUser = makeAddr("secondUser");

        vm.expectRevert(bytes("PoolManager/escrow-cannot-be-frozen"));
        centrifugeChain.freeze(poolId, trancheId, address(escrow));

        vm.expectRevert(bytes("PoolManager/unknown-token"));
        centrifugeChain.freeze(poolId + 1, trancheId, randomUser);

        vm.expectRevert(bytes("PoolManager/unknown-token"));
        centrifugeChain.unfreeze(poolId + 1, trancheId, randomUser);

        centrifugeChain.updateMember(poolId, trancheId, randomUser, validUntil);
        centrifugeChain.updateMember(poolId, trancheId, secondUser, validUntil);
        assertTrue(trancheToken.checkTransferRestriction(randomUser, secondUser, 0));

        centrifugeChain.freeze(poolId, trancheId, randomUser);
        assertFalse(trancheToken.checkTransferRestriction(randomUser, secondUser, 0));

        centrifugeChain.unfreeze(poolId, trancheId, randomUser);
        assertTrue(trancheToken.checkTransferRestriction(randomUser, secondUser, 0));

        centrifugeChain.freeze(poolId, trancheId, secondUser);
        assertFalse(trancheToken.checkTransferRestriction(randomUser, secondUser, 0));

        centrifugeChain.unfreeze(poolId, trancheId, secondUser);
        assertTrue(trancheToken.checkTransferRestriction(randomUser, secondUser, 0));
    }

    function testUpdateTokenMetadata() public {
        address lPool_ = deploySimplePool();
        LiquidityPool lPool = LiquidityPool(lPool_);
        uint64 poolId = lPool.poolId();
        bytes16 trancheId = lPool.trancheId();
        TrancheTokenLike trancheToken = TrancheTokenLike(address(LiquidityPool(lPool_).share()));

        string memory updatedTokenName = "newName";
        string memory updatedTokenSymbol = "newSymbol";

        vm.expectRevert(bytes("PoolManager/unknown-token"));
        centrifugeChain.updateTrancheTokenMetadata(100, bytes16(bytes("100")), updatedTokenName, updatedTokenSymbol);

        vm.expectRevert(bytes("Auth/not-authorized"));
        vm.prank(randomUser);
        poolManager.updateTrancheTokenMetadata(poolId, trancheId, updatedTokenName, updatedTokenSymbol);

        assertEq(trancheToken.name(), "name");
        assertEq(trancheToken.symbol(), "symbol");

        centrifugeChain.updateTrancheTokenMetadata(poolId, trancheId, updatedTokenName, updatedTokenSymbol);
        assertEq(trancheToken.name(), updatedTokenName);
        assertEq(trancheToken.symbol(), updatedTokenSymbol);

        vm.expectRevert(bytes("PoolManager/old-metadata"));
        centrifugeChain.updateTrancheTokenMetadata(poolId, trancheId, updatedTokenName, updatedTokenSymbol);
    }

    function testAllowInvestmentCurrency() public {
        uint128 currency = defaultCurrencyId;
        uint64 poolId = 1;

        centrifugeChain.addCurrency(currency, address(erc20));
        centrifugeChain.addPool(poolId);

        centrifugeChain.allowInvestmentCurrency(poolId, currency);
        assertTrue(poolManager.isAllowedAsset(poolId, address(erc20)));

        centrifugeChain.disallowInvestmentCurrency(poolId, currency);
        assertEq(poolManager.isAllowedAsset(poolId, address(erc20)), false);

        uint128 randomCurrency = 100;

        vm.expectRevert(bytes("PoolManager/unknown-currency"));
        centrifugeChain.allowInvestmentCurrency(poolId, randomCurrency);

        vm.expectRevert(bytes("PoolManager/invalid-pool"));
        centrifugeChain.allowInvestmentCurrency(poolId + 1, randomCurrency);

        vm.expectRevert(bytes("PoolManager/unknown-currency"));
        centrifugeChain.disallowInvestmentCurrency(poolId, randomCurrency);

        vm.expectRevert(bytes("PoolManager/invalid-pool"));
        centrifugeChain.disallowInvestmentCurrency(poolId + 1, randomCurrency);
    }

    function testUpdateTokenPriceWorks(
        uint64 poolId,
        uint8 decimals,
        uint8 restrictionSet,
        uint128 currencyId,
        string memory tokenName,
        string memory tokenSymbol,
        bytes16 trancheId,
        uint128 price
    ) public {
        decimals = uint8(bound(decimals, 1, 18));
        vm.assume(poolId > 0);
        vm.assume(trancheId > 0);
        vm.assume(currencyId > 0);
        centrifugeChain.addPool(poolId);

        vm.expectRevert(bytes("PoolManager/tranche-does-not-exist"));
        centrifugeChain.updateTrancheTokenPrice(poolId, trancheId, currencyId, price, uint64(block.timestamp));

        centrifugeChain.addTranche(poolId, trancheId, tokenName, tokenSymbol, decimals, restrictionSet);
        centrifugeChain.addCurrency(currencyId, address(erc20));
        centrifugeChain.allowInvestmentCurrency(poolId, currencyId);

        poolManager.deployTranche(poolId, trancheId);

        // Allows us to go back in time later
        vm.warp(block.timestamp + 1 days);

        vm.expectRevert(bytes("Auth/not-authorized"));
        vm.prank(randomUser);
        poolManager.updateTrancheTokenPrice(poolId, trancheId, currencyId, price, uint64(block.timestamp));

        centrifugeChain.updateTrancheTokenPrice(poolId, trancheId, currencyId, price, uint64(block.timestamp));
        (uint256 latestPrice, uint64 priceComputedAt) =
            poolManager.getTrancheTokenPrice(poolId, trancheId, address(erc20));
        assertEq(latestPrice, price);
        assertEq(priceComputedAt, block.timestamp);

        vm.expectRevert(bytes("PoolManager/cannot-set-older-price"));
        centrifugeChain.updateTrancheTokenPrice(poolId, trancheId, currencyId, price, uint64(block.timestamp - 1));
    }

    function testRemoveLiquidityPool() public {
        address lPool_ = deploySimplePool();
        LiquidityPool lPool = LiquidityPool(lPool_);
        uint64 poolId = lPool.poolId();
        bytes16 trancheId = lPool.trancheId();
        address currency = address(lPool.asset());
        address trancheToken_ = address(lPool.share());
        TrancheToken trancheToken = TrancheToken(trancheToken_);

        poolManager.deny(address(this));
        vm.expectRevert(bytes("Auth/not-authorized"));
        poolManager.removeLiquidityPool(poolId, trancheId, currency);

        root.relyContract(address(poolManager), address(this));

        vm.expectRevert(bytes("PoolManager/pool-does-not-exist"));
        poolManager.removeLiquidityPool(poolId + 1, trancheId, currency);

        vm.expectRevert(bytes("PoolManager/tranche-does-not-exist"));
        poolManager.removeLiquidityPool(poolId, bytes16(0), currency);

        poolManager.removeLiquidityPool(poolId, trancheId, currency);
        assertEq(poolManager.getLiquidityPool(poolId, trancheId, currency), address(0));
        assertEq(investmentManager.wards(lPool_), 0);
        assertEq(trancheToken.wards(lPool_), 0);
        assertEq(trancheToken.isTrustedForwarder(lPool_), false);
        assertEq(trancheToken.allowance(address(escrow), lPool_), 0);
    }

    function testRemoveLiquidityPoolFailsWhenLiquidityPoolNotDeployed() public {
        uint64 poolId = 5;
        bytes16 trancheId = bytes16(bytes("1"));

        centrifugeChain.addPool(poolId); // add pool
        centrifugeChain.addTranche(poolId, trancheId, "Test Token", "TT", 6, 2); // add tranche

        centrifugeChain.addCurrency(10, address(erc20));
        centrifugeChain.allowInvestmentCurrency(poolId, 10);
        poolManager.deployTranche(poolId, trancheId);

        vm.expectRevert(bytes("PoolManager/liquidity-pool-not-deployed"));
        poolManager.removeLiquidityPool(poolId, trancheId, address(erc20));
    }

    function testLiquidityPoolMigration() public {
        address oldLiquidityPool_ = deploySimplePool();

        LiquidityPool oldLiquidityPool = LiquidityPool(oldLiquidityPool_);
        uint64 poolId = oldLiquidityPool.poolId();
        bytes16 trancheId = oldLiquidityPool.trancheId();
        address currency = address(oldLiquidityPool.asset());

        LiquidityPoolFactory newLiquidityPoolFactory = new LiquidityPoolFactory(address(root));

        // rewire factory contracts
        newLiquidityPoolFactory.rely(address(poolManager));
        investmentManager.rely(address(newLiquidityPoolFactory));
        poolManager.file("liquidityPoolFactory", address(newLiquidityPoolFactory));

        // Remove old liquidity pool
        poolManager.removeLiquidityPool(poolId, trancheId, currency);
        assertEq(poolManager.getLiquidityPool(poolId, trancheId, currency), address(0));

        // Deploy new liquidity pool
        address newLiquidityPool = poolManager.deployLiquidityPool(poolId, trancheId, currency);
        assertEq(poolManager.getLiquidityPool(poolId, trancheId, currency), newLiquidityPool);
    }

    // helpers
    function hasDuplicates(bytes16[4] calldata array) internal pure returns (bool) {
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
