// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import "test/BaseTest.sol";
import "test/mocks/MockRestrictionManagerFactory.sol";
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

        address newVaultFactory = makeAddr("newVaultFactory");
        poolManager.file("vaultFactory", newVaultFactory);
        assertEq(address(poolManager.vaultFactory()), newVaultFactory);

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
        uint128 assetId
    ) public {
        vm.assume(assetId > 0);
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
        RestrictionManagerFactory restrictionManagerFactory = new RestrictionManagerFactory();
        poolManager.file("restrictionManagerFactory", address(restrictionManagerFactory));
        centrifugeChain.addPool(poolId);
        centrifugeChain.addTranche(poolId, trancheId, "", "", defaultDecimals, restrictionSet);
        poolManager.deployTranche(poolId, trancheId);
        // assert restrictionSet info is passed correctly to the factory
        assertEq(restrictionManagerFactory.values_uint8("restrictionSet"), restrictionSet);
    }

    function testAddAsset(uint128 assetId) public {
        uint128 badCurrency = 2;
        vm.assume(assetId > 0);
        vm.assume(assetId != badCurrency);
        ERC20 erc20_invalid_too_few = _newErc20("X's Dollar", "USDX", 0);
        ERC20 erc20_invalid_too_many = _newErc20("X's Dollar", "USDX", 42);

        vm.expectRevert(bytes("PoolManager/too-few-asset-decimals"));
        centrifugeChain.addAsset(assetId, address(erc20_invalid_too_few));

        vm.expectRevert(bytes("PoolManager/too-many-asset-decimals"));
        centrifugeChain.addAsset(assetId, address(erc20_invalid_too_many));

        vm.expectRevert(bytes("PoolManager/asset-id-has-to-be-greater-than-0"));
        centrifugeChain.addAsset(0, address(erc20));

        centrifugeChain.addAsset(assetId, address(erc20));

        // Verify we can't override the same asset id another address
        vm.expectRevert(bytes("PoolManager/asset-id-in-use"));
        centrifugeChain.addAsset(assetId, makeAddr("randomCurrency"));

        // Verify we can't add a asset address that already exists associated with a different aset id
        vm.expectRevert(bytes("PoolManager/asset-address-in-use"));
        centrifugeChain.addAsset(badCurrency, address(erc20));

        assertEq(poolManager.idToAsset(assetId), address(erc20));
    }

    function testDeployVault(
        uint64 poolId,
        uint8 decimals,
        uint8 restrictionSet,
        string memory tokenName,
        string memory tokenSymbol,
        bytes16 trancheId,
        uint128 assetId
    ) public {
        decimals = uint8(bound(decimals, 1, 18));
        vm.assume(assetId > 0);
        vm.assume(bytes(tokenName).length <= 128);
        vm.assume(bytes(tokenSymbol).length <= 32);

        centrifugeChain.addPool(poolId); // add pool
        centrifugeChain.addTranche(poolId, trancheId, tokenName, tokenSymbol, decimals, restrictionSet); // add tranche
        centrifugeChain.addAsset(assetId, address(erc20));

        vm.expectRevert(bytes("PoolManager/tranche-does-not-exist"));
        poolManager.deployVault(poolId, trancheId, address(erc20));
        address trancheToken_ = poolManager.deployTranche(poolId, trancheId);

        vm.expectRevert(bytes("PoolManager/asset-not-supported"));
        poolManager.deployVault(poolId, trancheId, address(erc20));
        centrifugeChain.allowAsset(poolId, assetId);

        address vaultAddress = poolManager.deployVault(poolId, trancheId, address(erc20));
        address vault_ = poolManager.getVault(poolId, trancheId, address(erc20));

        vm.expectRevert(bytes("PoolManager/vault-already-deployed"));
        poolManager.deployVault(poolId, trancheId, address(erc20));

        // make sure the pool was added to the tranche struct
        assertEq(vaultAddress, vault_);

        // check vault state
        ERC7540Vault vault = ERC7540Vault(vault_);
        TrancheToken trancheToken = TrancheToken(trancheToken_);
        assertEq(address(vault.manager()), address(investmentManager));
        assertEq(vault.asset(), address(erc20));
        assertEq(vault.poolId(), poolId);
        assertEq(vault.trancheId(), trancheId);
        assertEq(address(vault.share()), trancheToken_);
        assertTrue(vault.wards(address(investmentManager)) == 1);
        assertTrue(vault.wards(address(this)) == 0);
        assertTrue(investmentManager.wards(vaultAddress) == 1);

        assertEq(trancheToken.name(), tokenName);
        assertEq(trancheToken.symbol(), tokenSymbol);
        assertEq(trancheToken.decimals(), decimals);
        (, uint64 actualValidUntil) = RestrictionManagerLike(address(trancheToken.restrictionManager())).restrictions(
            address(investmentManager.escrow())
        );
        assertTrue(actualValidUntil >= block.timestamp);

        assertTrue(trancheToken.wards(address(poolManager)) == 1);
        assertTrue(trancheToken.wards(vault_) == 1);
        assertTrue(trancheToken.wards(address(this)) == 0);
        assertTrue(trancheToken.isTrustedForwarder(vault_)); // Lpool is not trusted forwarder on token
    }

    function testIncomingTransfer(uint128 amount) public {
        vm.assume(amount > 0);
        uint128 assetId = defaultAssetId;
        address recipient = makeAddr("recipient");
        bytes32 sender = makeAddr("sender").toBytes32();

        vm.expectRevert(bytes("PoolManager/unknown-asset"));
        centrifugeChain.incomingTransfer(assetId, sender, bytes32(bytes20(recipient)), amount);
        centrifugeChain.addAsset(assetId, address(erc20));

        vm.expectRevert(bytes("SafeTransferLib/safe-transfer-from-failed"));
        centrifugeChain.incomingTransfer(assetId, sender, bytes32(bytes20(recipient)), amount);

        vm.expectRevert(bytes("SafeTransferLib/safe-transfer-from-failed"));
        centrifugeChain.incomingTransfer(assetId, sender, bytes32(bytes20(recipient)), amount);

        erc20.mint(address(poolManager.escrow()), amount); // fund escrow

        // Now we test the incoming message
        centrifugeChain.incomingTransfer(assetId, sender, bytes32(bytes20(recipient)), amount);
        assertEq(erc20.balanceOf(address(poolManager.escrow())), 0);
        assertEq(erc20.balanceOf(recipient), amount);
    }

    // Verify that funds are moved from the msg.sender into the escrow account
    function testOutgoingTransfer(uint128 initialBalance, uint128 amount) public {
        initialBalance = uint128(bound(initialBalance, amount, type(uint128).max)); // initialBalance >= amount
        vm.assume(amount > 0);
        uint128 assetId = defaultAssetId;
        bytes32 recipient = makeAddr("recipient").toBytes32();

        erc20.mint(address(this), initialBalance);
        assertEq(erc20.balanceOf(address(this)), initialBalance);
        assertEq(erc20.balanceOf(address(poolManager.escrow())), 0);
        erc20.approve(address(poolManager), type(uint256).max);

        vm.expectRevert(bytes("PoolManager/unknown-asset"));
        poolManager.transfer(address(erc20), recipient, amount);
        centrifugeChain.addAsset(assetId, address(erc20));

        poolManager.transfer(address(erc20), recipient, amount);
        assertEq(erc20.balanceOf(address(this)), initialBalance - amount);
        assertEq(erc20.balanceOf(address(poolManager.escrow())), amount);
    }

    function testTransferTrancheTokensToCentrifuge(uint128 amount) public {
        vm.assume(amount > 0);
        uint64 validUntil = uint64(block.timestamp + 7 days);
        bytes32 centChainAddress = makeAddr("centChainAddress").toBytes32();
        address vault_ = deploySimpleVault();
        ERC7540Vault vault = ERC7540Vault(vault_);
        TrancheTokenLike trancheToken = TrancheTokenLike(address(ERC7540Vault(vault_).share()));

        // fund this account with amount
        centrifugeChain.updateMember(vault.poolId(), vault.trancheId(), address(this), validUntil);
        centrifugeChain.incomingTransferTrancheTokens(
            vault.poolId(), vault.trancheId(), uint64(block.chainid), address(this), amount
        );
        assertEq(trancheToken.balanceOf(address(this)), amount); // Verify the address(this) has the expected amount

        // fails for invalid tranche token
        uint64 poolId = vault.poolId();
        bytes16 trancheId = vault.trancheId();
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
        address vault_ = deploySimpleVault();
        ERC7540Vault vault = ERC7540Vault(vault_);
        uint64 poolId = vault.poolId();
        bytes16 trancheId = vault.trancheId();

        TrancheTokenLike trancheToken = TrancheTokenLike(address(vault.share()));

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

        address vault_ = deploySimpleVault();
        ERC7540Vault vault = ERC7540Vault(vault_);
        TrancheTokenLike trancheToken = TrancheTokenLike(address(ERC7540Vault(vault_).share()));

        centrifugeChain.updateMember(vault.poolId(), vault.trancheId(), destinationAddress, validUntil);
        centrifugeChain.updateMember(vault.poolId(), vault.trancheId(), address(this), validUntil);
        assertTrue(trancheToken.checkTransferRestriction(address(0), address(this), 0));
        assertTrue(trancheToken.checkTransferRestriction(address(0), destinationAddress, 0));

        // Fund this address with samount
        centrifugeChain.incomingTransferTrancheTokens(
            vault.poolId(), vault.trancheId(), uint64(block.chainid), address(this), amount
        );
        assertEq(trancheToken.balanceOf(address(this)), amount);

        // fails for invalid tranche token
        uint64 poolId = vault.poolId();
        bytes16 trancheId = vault.trancheId();
        vm.expectRevert(bytes("PoolManager/unknown-token"));
        poolManager.transferTrancheTokensToEVM(poolId + 1, trancheId, uint64(block.chainid), destinationAddress, amount);

        // Approve and transfer amount from this address to destinationAddress
        trancheToken.approve(address(poolManager), amount);
        poolManager.transferTrancheTokensToEVM(
            vault.poolId(), vault.trancheId(), uint64(block.chainid), destinationAddress, amount
        );
        assertEq(trancheToken.balanceOf(address(this)), 0);
    }

    function testUpdateMember(uint64 validUntil) public {
        validUntil = uint64(bound(validUntil, block.timestamp, type(uint64).max));
        address vault_ = deploySimpleVault();
        ERC7540Vault vault = ERC7540Vault(vault_);
        TrancheTokenLike trancheToken = TrancheTokenLike(address(ERC7540Vault(vault_).share()));

        uint64 poolId = vault.poolId();
        bytes16 trancheId = vault.trancheId();
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
        address vault_ = deploySimpleVault();
        ERC7540Vault vault = ERC7540Vault(vault_);
        uint64 poolId = vault.poolId();
        bytes16 trancheId = vault.trancheId();
        TrancheTokenLike trancheToken = TrancheTokenLike(address(ERC7540Vault(vault_).share()));
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
        address vault_ = deploySimpleVault();
        ERC7540Vault vault = ERC7540Vault(vault_);
        uint64 poolId = vault.poolId();
        bytes16 trancheId = vault.trancheId();
        TrancheTokenLike trancheToken = TrancheTokenLike(address(ERC7540Vault(vault_).share()));

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

    function testAllowAsset() public {
        uint128 assetId = defaultAssetId;
        uint64 poolId = 1;

        centrifugeChain.addAsset(assetId, address(erc20));
        centrifugeChain.addPool(poolId);

        centrifugeChain.allowAsset(poolId, assetId);
        assertTrue(poolManager.isAllowedAsset(poolId, address(erc20)));

        centrifugeChain.disallowAsset(poolId, assetId);
        assertEq(poolManager.isAllowedAsset(poolId, address(erc20)), false);

        uint128 randomCurrency = 100;

        vm.expectRevert(bytes("PoolManager/unknown-asset"));
        centrifugeChain.allowAsset(poolId, randomCurrency);

        vm.expectRevert(bytes("PoolManager/invalid-pool"));
        centrifugeChain.allowAsset(poolId + 1, randomCurrency);

        vm.expectRevert(bytes("PoolManager/unknown-asset"));
        centrifugeChain.disallowAsset(poolId, randomCurrency);

        vm.expectRevert(bytes("PoolManager/invalid-pool"));
        centrifugeChain.disallowAsset(poolId + 1, randomCurrency);
    }

    function testUpdateTokenPriceWorks(
        uint64 poolId,
        uint8 decimals,
        uint8 restrictionSet,
        uint128 assetId,
        string memory tokenName,
        string memory tokenSymbol,
        bytes16 trancheId,
        uint128 price
    ) public {
        decimals = uint8(bound(decimals, 1, 18));
        vm.assume(poolId > 0);
        vm.assume(trancheId > 0);
        vm.assume(assetId > 0);
        centrifugeChain.addPool(poolId);

        vm.expectRevert(bytes("PoolManager/tranche-does-not-exist"));
        centrifugeChain.updateTrancheTokenPrice(poolId, trancheId, assetId, price, uint64(block.timestamp));

        centrifugeChain.addTranche(poolId, trancheId, tokenName, tokenSymbol, decimals, restrictionSet);
        centrifugeChain.addAsset(assetId, address(erc20));
        centrifugeChain.allowAsset(poolId, assetId);

        poolManager.deployTranche(poolId, trancheId);

        // Allows us to go back in time later
        vm.warp(block.timestamp + 1 days);

        vm.expectRevert(bytes("Auth/not-authorized"));
        vm.prank(randomUser);
        poolManager.updateTrancheTokenPrice(poolId, trancheId, assetId, price, uint64(block.timestamp));

        centrifugeChain.updateTrancheTokenPrice(poolId, trancheId, assetId, price, uint64(block.timestamp));
        (uint256 latestPrice, uint64 priceComputedAt) =
            poolManager.getTrancheTokenPrice(poolId, trancheId, address(erc20));
        assertEq(latestPrice, price);
        assertEq(priceComputedAt, block.timestamp);

        vm.expectRevert(bytes("PoolManager/cannot-set-older-price"));
        centrifugeChain.updateTrancheTokenPrice(poolId, trancheId, assetId, price, uint64(block.timestamp - 1));
    }

    function testRemoveVault() public {
        address vault_ = deploySimpleVault();
        ERC7540Vault vault = ERC7540Vault(vault_);
        uint64 poolId = vault.poolId();
        bytes16 trancheId = vault.trancheId();
        address asset = address(vault.asset());
        address trancheToken_ = address(vault.share());
        TrancheToken trancheToken = TrancheToken(trancheToken_);

        poolManager.deny(address(this));
        vm.expectRevert(bytes("Auth/not-authorized"));
        poolManager.removeVault(poolId, trancheId, asset);

        root.relyContract(address(poolManager), address(this));

        vm.expectRevert(bytes("PoolManager/pool-does-not-exist"));
        poolManager.removeVault(poolId + 1, trancheId, asset);

        vm.expectRevert(bytes("PoolManager/tranche-does-not-exist"));
        poolManager.removeVault(poolId, bytes16(0), asset);

        poolManager.removeVault(poolId, trancheId, asset);
        assertEq(poolManager.getVault(poolId, trancheId, asset), address(0));
        assertEq(investmentManager.wards(vault_), 0);
        assertEq(trancheToken.wards(vault_), 0);
        assertEq(trancheToken.isTrustedForwarder(vault_), false);
        assertEq(trancheToken.allowance(address(escrow), vault_), 0);
    }

    function testRemoveVaultFailsWhenVaultNotDeployed() public {
        uint64 poolId = 5;
        bytes16 trancheId = bytes16(bytes("1"));

        centrifugeChain.addPool(poolId); // add pool
        centrifugeChain.addTranche(poolId, trancheId, "Test Token", "TT", 6, 2); // add tranche

        centrifugeChain.addAsset(10, address(erc20));
        centrifugeChain.allowAsset(poolId, 10);
        poolManager.deployTranche(poolId, trancheId);

        vm.expectRevert(bytes("PoolManager/vault-not-deployed"));
        poolManager.removeVault(poolId, trancheId, address(erc20));
    }

    function testVaultMigration() public {
        address oldVault_ = deploySimpleVault();

        ERC7540Vault oldVault = ERC7540Vault(oldVault_);
        uint64 poolId = oldVault.poolId();
        bytes16 trancheId = oldVault.trancheId();
        address asset = address(oldVault.asset());

        ERC7540VaultFactory newVaultFactory = new ERC7540VaultFactory(address(root));

        // rewire factory contracts
        newVaultFactory.rely(address(poolManager));
        investmentManager.rely(address(newVaultFactory));
        poolManager.file("vaultFactory", address(newVaultFactory));

        // Remove old vault
        poolManager.removeVault(poolId, trancheId, asset);
        assertEq(poolManager.getVault(poolId, trancheId, asset), address(0));

        // Deploy new vault
        address newVault = poolManager.deployVault(poolId, trancheId, asset);
        assertEq(poolManager.getVault(poolId, trancheId, asset), newVault);
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
