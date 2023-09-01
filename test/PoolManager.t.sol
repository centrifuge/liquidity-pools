// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.18;
pragma abicoder v2;

import "./TestSetup.t.sol";

contract PoolManagerTest is TestSetup {
    function testAddCurrencyWorks(uint128 currency, uint128 badCurrency) public {
        vm.assume(currency > 0);
        vm.assume(badCurrency > 0);
        vm.assume(currency != badCurrency);

        ERC20 erc20 = newErc20("X's Dollar", "USDX", 18);
        homePools.addCurrency(currency, address(erc20));
        (address address_) = evmPoolManager.currencyIdToAddress(currency);
        assertEq(address_, address(erc20));

        // Verify we can't override the same currency id another address
        ERC20 badErc20 = newErc20("BadActor's Dollar", "BADUSD", 18);
        vm.expectRevert(bytes("PoolManager/currency-id-in-use"));
        homePools.addCurrency(currency, address(badErc20));
        assertEq(evmPoolManager.currencyIdToAddress(currency), address(erc20));

        // Verify we can't add a currency address that already exists associated with a different currency id
        vm.expectRevert(bytes("PoolManager/currency-address-in-use"));
        homePools.addCurrency(badCurrency, address(erc20));
        assertEq(evmPoolManager.currencyIdToAddress(currency), address(erc20));
    }

    function testAddCurrencyHasMaxDecimals() public {
        ERC20 erc20_invalid = newErc20("X's Dollar", "USDX", 42);
        vm.expectRevert(bytes("PoolManager/too-many-currency-decimals"));
        homePools.addCurrency(1, address(erc20_invalid));

        ERC20 erc20_valid = newErc20("X's Dollar", "USDX", 18);
        homePools.addCurrency(2, address(erc20_valid));

        ERC20 erc20_valid2 = newErc20("X's Dollar", "USDX", 6);
        homePools.addCurrency(3, address(erc20_valid2));
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
        vm.assume(decimals <= 18);
        vm.assume(currency > 0);
        vm.assume(amount > 0);
        vm.assume(recipient != address(0));

        ERC20 erc20 = newErc20(tokenName, tokenSymbol, decimals);
        vm.assume(recipient != address(erc20));
        homePools.addCurrency(currency, address(erc20));

        assertEq(erc20.balanceOf(address(evmPoolManager.escrow())), 0);
        vm.expectRevert(bytes("ERC20/insufficient-balance"));
        homePools.incomingTransfer(currency, sender, bytes32(bytes20(recipient)), amount);
        assertEq(erc20.balanceOf(address(evmPoolManager.escrow())), 0);
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
        vm.assume(decimals <= 18);
        vm.assume(amount > 0);
        vm.assume(currency != 0);
        vm.assume(recipient != address(0));

        ERC20 erc20 = newErc20(tokenName, tokenSymbol, decimals);
        homePools.addCurrency(currency, address(erc20));

        // First, an outgoing transfer must take place which has funds currency of the currency moved to
        // the escrow account, from which funds are moved from into the recipient on an incoming transfer.
        erc20.approve(address(evmPoolManager), type(uint256).max);
        erc20.mint(address(this), amount);
        evmPoolManager.transfer(address(erc20), bytes32(bytes20(recipient)), amount);
        assertEq(erc20.balanceOf(address(evmPoolManager.escrow())), amount);

        // Now we test the incoming message
        homePools.incomingTransfer(currency, sender, bytes32(bytes20(recipient)), amount);
        assertEq(erc20.balanceOf(address(evmPoolManager.escrow())), 0);
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
        vm.assume(decimals <= 18);
        vm.assume(amount > 0);
        vm.assume(currency != 0);
        vm.assume(initialBalance >= amount);

        ERC20 erc20 = newErc20(tokenName, tokenSymbol, decimals);

        vm.expectRevert(bytes("PoolManager/unknown-currency"));
        evmPoolManager.transfer(address(erc20), recipient, amount);
        homePools.addCurrency(currency, address(erc20));

        erc20.mint(address(this), initialBalance);
        assertEq(erc20.balanceOf(address(this)), initialBalance);
        assertEq(erc20.balanceOf(address(evmPoolManager.escrow())), 0);
        erc20.approve(address(evmPoolManager), type(uint256).max);

        evmPoolManager.transfer(address(erc20), recipient, amount);
        assertEq(erc20.balanceOf(address(this)), initialBalance - amount);
        assertEq(erc20.balanceOf(address(evmPoolManager.escrow())), amount);
    }

    function testTransferTrancheTokensToCentrifuge(
        uint64 validUntil,
        bytes32 centChainAddress,
        uint128 amount,
        uint64 poolId,
        uint8 decimals,
        string memory tokenName,
        string memory tokenSymbol,
        bytes16 trancheId,
        uint128 currency,
        uint128 price
    ) public {
        vm.assume(decimals <= 18);
        vm.assume(currency > 0);
        vm.assume(validUntil > block.timestamp + 7 days);

        address lPool_ = deployLiquidityPool(poolId, decimals, tokenName, tokenSymbol, trancheId, price, currency);
        homePools.updateMember(poolId, trancheId, address(this), validUntil);

        // fund this account with amount
        homePools.incomingTransferTrancheTokens(poolId, trancheId, uint64(block.chainid), address(this), amount);

        // Verify the address(this) has the expected amount
        assertEq(LiquidityPool(lPool_).balanceOf(address(this)), amount);

        // Now send the transfer from EVM -> Cent Chain
        LiquidityPool(lPool_).approve(address(evmPoolManager), amount);
        evmPoolManager.transferTrancheTokensToCentrifuge(poolId, trancheId, centChainAddress, amount);
        assertEq(LiquidityPool(lPool_).balanceOf(address(this)), 0);

        // Finally, verify the connector called `router.send`
        bytes memory message = Messages.formatTransferTrancheTokens(
            poolId,
            trancheId,
            bytes32(bytes20(address(this))),
            Messages.formatDomain(Messages.Domain.Centrifuge),
            centChainAddress,
            amount
        );
        assertEq(mockXcmRouter.sentMessages(message), true);
    }

    function testTransferTrancheTokensFromCentrifuge(
        uint64 poolId,
        uint8 decimals,
        string memory tokenName,
        string memory tokenSymbol,
        bytes16 trancheId,
        uint128 currency,
        uint64 validUntil,
        address destinationAddress,
        uint128 amount,
        uint128 price
    ) public {
        vm.assume(decimals <= 18);
        vm.assume(validUntil >= block.timestamp);
        vm.assume(destinationAddress != address(0));
        vm.assume(currency > 0);

        address lPool_ = deployLiquidityPool(poolId, decimals, tokenName, tokenSymbol, trancheId, price, currency);

        homePools.updateMember(poolId, trancheId, destinationAddress, validUntil);
        assertTrue(LiquidityPool(lPool_).hasMember(destinationAddress));
        homePools.incomingTransferTrancheTokens(poolId, trancheId, uint64(block.chainid), destinationAddress, amount);
        assertEq(LiquidityPool(lPool_).balanceOf(destinationAddress), amount);
    }

    function testTransferTrancheTokensFromCentrifugeWithoutMemberFails(
        uint64 poolId,
        uint8 decimals,
        string memory tokenName,
        string memory tokenSymbol,
        bytes16 trancheId,
        uint128 currency,
        address destinationAddress,
        uint128 amount,
        uint128 price
    ) public {
        vm.assume(decimals <= 18);
        vm.assume(destinationAddress != address(0));
        vm.assume(currency > 0);

        deployLiquidityPool(poolId, decimals, tokenName, tokenSymbol, trancheId, price, currency);

        vm.expectRevert(bytes("PoolManager/not-a-member"));
        homePools.incomingTransferTrancheTokens(poolId, trancheId, uint64(block.chainid), destinationAddress, amount);
    }

    function testTransferTrancheTokensToEVM(
        uint64 poolId,
        bytes16 trancheId,
        string memory tokenName,
        string memory tokenSymbol,
        uint8 decimals,
        uint64 validUntil,
        address destinationAddress,
        uint128 amount,
        uint128 currency,
        uint128 price
    ) public {
        vm.assume(decimals <= 18);
        vm.assume(validUntil > block.timestamp + 7 days);
        vm.assume(destinationAddress != address(0));
        vm.assume(currency > 0);
        vm.assume(amount > 0);
        address lPool_ = deployLiquidityPool(poolId, decimals, tokenName, tokenSymbol, trancheId, price, currency);
        homePools.updateMember(poolId, trancheId, destinationAddress, validUntil);
        homePools.updateMember(poolId, trancheId, address(this), validUntil);
        assertTrue(LiquidityPool(lPool_).hasMember(address(this)));
        assertTrue(LiquidityPool(lPool_).hasMember(destinationAddress));

        // Fund this address with amount
        homePools.incomingTransferTrancheTokens(poolId, trancheId, uint64(block.chainid), address(this), amount);
        assertEq(LiquidityPool(lPool_).balanceOf(address(this)), amount);

        // Approve and transfer amount from this address to destinationAddress
        LiquidityPool(lPool_).approve(address(evmPoolManager), amount);
        console.logAddress(lPool_);
        console.logAddress(LiquidityPool(lPool_).asset());
        evmPoolManager.transferTrancheTokensToEVM(poolId, trancheId, uint64(block.chainid), destinationAddress, amount);
        assertEq(LiquidityPool(lPool_).balanceOf(address(this)), 0);
    }

    function testUpdatingMemberWorks(
        uint64 poolId,
        uint8 decimals,
        uint128 currency,
        string memory tokenName,
        string memory tokenSymbol,
        bytes16 trancheId,
        address user,
        uint64 validUntil,
        uint128 price
    ) public {
        vm.assume(decimals <= 18);
        vm.assume(validUntil >= block.timestamp);
        vm.assume(user != address(0));
        vm.assume(currency > 0);
        ERC20 erc20 = newErc20("X's Dollar", "USDX", 18);
        homePools.addPool(poolId); // add pool
        homePools.addTranche(poolId, trancheId, tokenName, tokenSymbol, decimals, price); // add tranche
        homePools.addCurrency(currency, address(erc20));
        homePools.allowPoolCurrency(poolId, currency);
        evmPoolManager.deployTranche(poolId, trancheId);
        address lPool_ = evmPoolManager.deployLiquidityPool(poolId, trancheId, address(erc20));

        homePools.updateMember(poolId, trancheId, user, validUntil);
        assertTrue(LiquidityPool(lPool_).hasMember(user));
    }

    function testUpdatingMemberAsNonRouterFails(
        uint64 poolId,
        uint128 currency,
        bytes16 trancheId,
        address user,
        uint64 validUntil
    ) public {
        vm.assume(validUntil >= block.timestamp);
        vm.assume(user != address(0));
        vm.assume(currency > 0);

        vm.expectRevert(bytes("PoolManager/not-the-gateway"));
        evmPoolManager.updateMember(poolId, trancheId, user, validUntil);
    }

    function testUpdatingMemberForNonExistentTrancheFails(
        uint64 poolId,
        bytes16 trancheId,
        address user,
        uint64 validUntil
    ) public {
        vm.assume(validUntil > block.timestamp);
        homePools.addPool(poolId);

        vm.expectRevert(bytes("PoolManager/unknown-token"));
        homePools.updateMember(poolId, trancheId, user, validUntil);
    }

    function testUpdatingTokenPriceWorks(
        uint64 poolId,
        uint8 decimals,
        uint128 currency,
        string memory tokenName,
        string memory tokenSymbol,
        bytes16 trancheId,
        uint128 price
    ) public {
        vm.assume(decimals <= 18);
        vm.assume(currency > 0);
        vm.assume(poolId > 0);
        vm.assume(trancheId > 0);
        homePools.addPool(poolId); // add pool
        homePools.addTranche(poolId, trancheId, tokenName, tokenSymbol, decimals, price); // add tranche

        address tranche_ = evmPoolManager.deployTranche(poolId, trancheId);

        homePools.updateTrancheTokenPrice(poolId, trancheId, price);
        assertEq(TrancheToken(tranche_).latestPrice(), price);
        assertEq(TrancheToken(tranche_).lastPriceUpdate(), block.timestamp);
    }

    function testUpdatingTokenPriceAsNonRouterFails(
        uint64 poolId,
        uint8 decimals,
        uint128 currency,
        string memory tokenName,
        string memory tokenSymbol,
        bytes16 trancheId,
        uint128 price
    ) public {
        vm.assume(decimals <= 18);
        vm.assume(currency > 0);
        ERC20 erc20 = newErc20("X's Dollar", "USDX", 18);
        homePools.addPool(poolId); // add pool
        homePools.addTranche(poolId, trancheId, tokenName, tokenSymbol, decimals, price); // add tranche
        homePools.addCurrency(currency, address(erc20));
        homePools.allowPoolCurrency(poolId, currency);
        evmPoolManager.deployTranche(poolId, trancheId);
        evmPoolManager.deployLiquidityPool(poolId, trancheId, address(erc20));

        vm.expectRevert(bytes("PoolManager/not-the-gateway"));
        evmPoolManager.updateTrancheTokenPrice(poolId, trancheId, price);
    }

    function testUpdatingTokenPriceForNonExistentTrancheFails(uint64 poolId, bytes16 trancheId, uint128 price) public {
        homePools.addPool(poolId);

        vm.expectRevert(bytes("PoolManager/unknown-token"));
        homePools.updateTrancheTokenPrice(poolId, trancheId, price);
    }

    function testUpdatingTokenMetadataWorks(
        uint64 poolId,
        uint8 decimals,
        uint128 currency,
        string memory tokenName,
        string memory tokenSymbol,
        bytes16 trancheId,
        uint128 price,
        string memory updatedTokenName,
        string memory updatedTokenSymbol
    ) public {
        vm.assume(decimals <= 18);
        vm.assume(currency > 0);
        homePools.addPool(poolId); // add pool
        homePools.addTranche(poolId, trancheId, tokenName, tokenSymbol, decimals, price); // add tranche

        evmPoolManager.deployTranche(poolId, trancheId);

        homePools.updateTrancheTokenMetadata(poolId, trancheId, updatedTokenName, updatedTokenSymbol);
    }

    function testUpdatingTokenMetadataAsNonRouterFails(
        uint64 poolId,
        uint8 decimals,
        uint128 currency,
        string memory tokenName,
        string memory tokenSymbol,
        bytes16 trancheId,
        uint128 price,
        string memory updatedTokenName,
        string memory updatedTokenSymbol
    ) public {
        vm.assume(decimals <= 18);
        vm.assume(currency > 0);
        ERC20 erc20 = newErc20("X's Dollar", "USDX", 18);
        homePools.addPool(poolId); // add pool
        homePools.addTranche(poolId, trancheId, tokenName, tokenSymbol, decimals, price); // add tranche
        homePools.addCurrency(currency, address(erc20));
        homePools.allowPoolCurrency(poolId, currency);
        evmPoolManager.deployTranche(poolId, trancheId);
        evmPoolManager.deployLiquidityPool(poolId, trancheId, address(erc20));

        vm.expectRevert(bytes("PoolManager/not-the-gateway"));
        evmPoolManager.updateTrancheTokenMetadata(poolId, trancheId, updatedTokenName, updatedTokenSymbol);
    }

    function testUpdatingTokenMetadataForNonExistentTrancheFails(
        uint64 poolId,
        bytes16 trancheId,
        string memory updatedTokenName,
        string memory updatedTokenSymbol
    ) public {
        homePools.addPool(poolId);

        vm.expectRevert(bytes("PoolManager/unknown-token"));
        homePools.updateTrancheTokenMetadata(poolId, trancheId, updatedTokenName, updatedTokenSymbol);
    }

    function testAddPoolWorks(uint64 poolId) public {
        homePools.addPool(poolId);
        (, uint64 actualPoolId,) = evmPoolManager.pools(poolId);
        assertEq(uint256(actualPoolId), uint256(poolId));
    }

    function testAllowPoolCurrencyWorks(uint128 currency, uint64 poolId) public {
        vm.assume(currency > 0);
        ERC20 token = newErc20("X's Dollar", "USDX", 18);
        homePools.addCurrency(currency, address(token));
        homePools.addPool(poolId);

        homePools.allowPoolCurrency(poolId, currency);
        assertTrue(evmPoolManager.isAllowedAsPoolCurrency(poolId, address(token)));
    }

    function testAllowPoolCurrencyWithUnknownCurrencyFails(uint128 currency, uint64 poolId) public {
        homePools.addPool(poolId);
        vm.expectRevert(bytes("PoolManager/unknown-currency"));
        homePools.allowPoolCurrency(poolId, currency);
    }

    function testAddingPoolMultipleTimesFails(uint64 poolId) public {
        homePools.addPool(poolId);

        vm.expectRevert(bytes("PoolManager/pool-already-added"));
        homePools.addPool(poolId);
    }

    function testAddingPoolAsNonRouterFails(uint64 poolId) public {
        vm.expectRevert(bytes("PoolManager/not-the-gateway"));
        evmPoolManager.addPool(poolId);
    }

    function testAddingSingleTrancheWorks(
        uint64 poolId,
        bytes16 trancheId,
        string memory tokenName,
        string memory tokenSymbol,
        uint8 decimals,
        uint128 price
    ) public {
        homePools.addPool(poolId);
        (, uint64 actualPoolId,) = evmPoolManager.pools(poolId);
        assertEq(uint256(actualPoolId), uint256(poolId));
        homePools.addTranche(poolId, trancheId, tokenName, tokenSymbol, decimals, price);
        evmPoolManager.deployTranche(poolId, trancheId);

        TrancheToken trancheToken = TrancheToken(evmPoolManager.getTrancheToken(poolId, trancheId));

        assertEq(bytes32ToString(stringToBytes32(tokenName)), bytes32ToString(stringToBytes32(trancheToken.name())));
        assertEq(bytes32ToString(stringToBytes32(tokenSymbol)), bytes32ToString(stringToBytes32(trancheToken.symbol())));
        assertEq(decimals, trancheToken.decimals());
    }

    function testAddingTrancheMultipleTimesFails(
        uint64 poolId,
        uint8 decimals,
        string memory tokenName,
        string memory tokenSymbol,
        bytes16 trancheId,
        uint128 price
    ) public {
        homePools.addPool(poolId);
        homePools.addTranche(poolId, trancheId, tokenName, tokenSymbol, decimals, price);

        vm.expectRevert(bytes("PoolManager/tranche-already-exists"));
        homePools.addTranche(poolId, trancheId, tokenName, tokenSymbol, decimals, price);
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
        homePools.addPool(poolId);

        for (uint256 i = 0; i < trancheIds.length; i++) {
            homePools.addTranche(poolId, trancheIds[i], tokenName, tokenSymbol, decimals, price);
            evmPoolManager.deployTranche(poolId, trancheIds[i]);
            TrancheToken trancheToken = TrancheToken(evmPoolManager.getTrancheToken(poolId, trancheIds[i]));
            assertEq(decimals, trancheToken.decimals());
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
        homePools.addPool(poolId);
        vm.expectRevert(bytes("PoolManager/not-the-gateway"));
        evmPoolManager.addTranche(poolId, trancheId, tokenName, tokenSymbol, decimals, price);
    }

    function testAddingTranchesForNonExistentPoolFails(
        uint64 poolId,
        bytes16 trancheId,
        string memory tokenName,
        string memory tokenSymbol,
        uint8 decimals,
        uint128 price
    ) public {
        vm.expectRevert(bytes("PoolManager/invalid-pool"));
        homePools.addTranche(poolId, trancheId, tokenName, tokenSymbol, decimals, price);
    }

    function testDeployLiquidityPool(
        uint64 poolId,
        uint8 decimals,
        string memory tokenName,
        string memory tokenSymbol,
        bytes16 trancheId,
        uint128 price,
        uint128 currency
    ) public {
        vm.assume(currency > 0);
        ERC20 erc20 = newErc20("X's Dollar", "USDX", 18);
        homePools.addPool(poolId); // add pool
        homePools.addTranche(poolId, trancheId, tokenName, tokenSymbol, decimals, price); // add tranche

        homePools.addCurrency(currency, address(erc20));
        homePools.allowPoolCurrency(poolId, currency);

        address trancheToken_ = evmPoolManager.deployTranche(poolId, trancheId);
        address lPoolAddress = evmPoolManager.deployLiquidityPool(poolId, trancheId, address(erc20));
        address lPool_ = evmPoolManager.getLiquidityPool(poolId, trancheId, address(erc20)); // make sure the pool was stored in LP

        // make sure the pool was added to the tranche struct
        assertEq(lPoolAddress, lPool_);

        // check LiquidityPool state
        LiquidityPool lPool = LiquidityPool(lPool_);
        TrancheToken trancheToken = TrancheToken(trancheToken_);
        assertEq(address(lPool.investmentManager()), address(evmInvestmentManager));
        assertEq(lPool.asset(), address(erc20));
        assertEq(lPool.poolId(), poolId);
        assertEq(lPool.trancheId(), trancheId);

        assertTrue(lPool.wards(address(evmInvestmentManager)) == 1);
        assertTrue(lPool.wards(address(this)) == 0);
        assertTrue(evmInvestmentManager.wards(lPoolAddress) == 1);

        assertEq(trancheToken.name(), bytes32ToString(stringToBytes32(tokenName)));
        assertEq(trancheToken.symbol(), bytes32ToString(stringToBytes32(tokenSymbol)));
        assertEq(trancheToken.decimals(), decimals);
        assertTrue(trancheToken.hasMember(address(evmInvestmentManager.escrow())));

        assertTrue(trancheToken.wards(address(evmPoolManager)) == 1);
        assertTrue(trancheToken.wards(lPool_) == 1);
        assertTrue(trancheToken.wards(address(this)) == 0);

        assert(trancheToken.isTrustedForwarder(lPool_) == true); // Lpool is not trusted forwarder on token
    }

    function testDeployingLiquidityPoolNonExistingTrancheFails(
        uint64 poolId,
        uint8 decimals,
        string memory tokenName,
        string memory tokenSymbol,
        bytes16 trancheId,
        bytes16 wrongTrancheId,
        uint128 price,
        uint128 currency
    ) public {
        vm.assume(currency > 0);
        vm.assume(trancheId != wrongTrancheId);

        ERC20 erc20 = newErc20("X's Dollar", "USDX", 18);
        homePools.addPool(poolId); // add pool
        homePools.addTranche(poolId, trancheId, tokenName, tokenSymbol, decimals, price); // add tranche

        homePools.addCurrency(currency, address(erc20));
        homePools.allowPoolCurrency(poolId, currency);
        vm.expectRevert(bytes("PoolManager/tranche-does-not-exist"));
        evmPoolManager.deployLiquidityPool(poolId, wrongTrancheId, address(erc20));
    }

    function testDeployingLiquidityPoolNonExistingPoolFails(
        uint64 poolId,
        uint8 decimals,
        string memory tokenName,
        string memory tokenSymbol,
        bytes16 trancheId,
        uint64 wrongPoolId,
        uint128 price,
        uint128 currency
    ) public {
        vm.assume(currency > 0);
        vm.assume(poolId != wrongPoolId);

        ERC20 erc20 = newErc20("X's Dollar", "USDX", 18);
        homePools.addPool(poolId); // add pool
        homePools.addTranche(poolId, trancheId, tokenName, tokenSymbol, decimals, price); // add tranche

        homePools.addCurrency(currency, address(erc20));
        homePools.allowPoolCurrency(poolId, currency);
        vm.expectRevert(bytes("PoolManager/tranche-does-not-exist"));
        evmPoolManager.deployLiquidityPool(wrongPoolId, trancheId, address(erc20));
    }

    function testDeployingLiquidityPoolCurrencyNotSupportedFails(
        uint64 poolId,
        uint8 decimals,
        string memory tokenName,
        string memory tokenSymbol,
        bytes16 trancheId,
        uint128 price,
        uint128 currency
    ) public {
        vm.assume(currency > 0);

        ERC20 erc20 = newErc20("X's Dollar", "USDX", 18);
        homePools.addPool(poolId); // add pool
        homePools.addTranche(poolId, trancheId, tokenName, tokenSymbol, decimals, price); // add tranche
        evmPoolManager.deployTranche(poolId, trancheId);

        homePools.addCurrency(currency, address(erc20));

        vm.expectRevert(bytes("PoolManager/pool-currency-not-allowed"));
        evmPoolManager.deployLiquidityPool(poolId, trancheId, address(erc20));
    }

    function testDeployLiquidityPoolTwiceFails(
        uint64 poolId,
        uint8 decimals,
        string memory tokenName,
        string memory tokenSymbol,
        bytes16 trancheId,
        uint128 price,
        uint128 currency
    ) public {
        vm.assume(currency > 0);
        ERC20 erc20 = newErc20("X's Dollar", "USDX", 18);

        homePools.addPool(poolId); // add pool
        homePools.addTranche(poolId, trancheId, tokenName, tokenSymbol, decimals, price); // add tranche

        homePools.addCurrency(currency, address(erc20));
        homePools.allowPoolCurrency(poolId, currency);
        evmPoolManager.deployTranche(poolId, trancheId);

        evmPoolManager.deployLiquidityPool(poolId, trancheId, address(erc20));
        vm.expectRevert(bytes("PoolManager/liquidityPool-already-deployed"));
        evmPoolManager.deployLiquidityPool(poolId, trancheId, address(erc20));
    }

    // helpers
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
