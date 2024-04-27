// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import "./../BaseTest.sol";

contract AssetShareConversionTest is BaseTest {
    function testAssetShareConversion(uint64 poolId, bytes16 trancheId, uint128 assetId) public {
        vm.assume(assetId > 0);

        uint8 INVESTMENT_CURRENCY_DECIMALS = 6; // 6, like USDC
        uint8 TRANCHE_TOKEN_DECIMALS = 18; // Like DAI

        ERC20 asset = _newErc20("Asset", "A", INVESTMENT_CURRENCY_DECIMALS);
        address vault_ = deployVault(
            poolId, TRANCHE_TOKEN_DECIMALS, defaultRestrictionSet, "", "", trancheId, assetId, address(asset)
        );
        ERC7540Vault vault = ERC7540Vault(vault_);
        TrancheTokenLike trancheToken = TrancheTokenLike(address(ERC7540Vault(vault_).share()));

        assertEq(vault.priceLastUpdated(), 0);
        centrifugeChain.updateTrancheTokenPrice(poolId, trancheId, assetId, 1000000, uint64(block.timestamp));
        assertEq(vault.priceLastUpdated(), uint64(block.timestamp));

        // invest
        uint256 investmentAmount = 100000000; // 100 * 10**6
        centrifugeChain.updateMember(poolId, trancheId, self, type(uint64).max);
        asset.approve(vault_, investmentAmount);
        asset.mint(self, investmentAmount);
        vault.requestDeposit(investmentAmount, self, self, "");

        // trigger executed collectInvest at a price of 1.0
        uint128 _assetId = poolManager.assetToId(address(asset)); // retrieve assetId
        uint128 shares = 100000000000000000000; // 100 * 10**18
        centrifugeChain.isFulfilledDepositRequest(
            poolId, trancheId, bytes32(bytes20(self)), _assetId, uint128(investmentAmount), shares, 0
        );
        vault.mint(shares, self);
        centrifugeChain.updateTrancheTokenPrice(
            poolId, trancheId, assetId, 1000000000000000000, uint64(block.timestamp)
        );

        // assert share/asset conversion
        assertEq(trancheToken.totalSupply(), 100000000000000000000);
        assertEq(vault.totalAssets(), 100000000);
        assertEq(vault.convertToShares(100000000), 100000000000000000000); // tranche tokens have 12 more decimals than
            // assets
        assertEq(vault.convertToAssets(vault.convertToShares(100000000000000000000)), 100000000000000000000);

        // assert share/asset conversion after price update
        centrifugeChain.updateTrancheTokenPrice(
            poolId, trancheId, assetId, 1200000000000000000, uint64(block.timestamp)
        );

        assertEq(vault.totalAssets(), 120000000);
        assertEq(vault.convertToShares(120000000), 100000000000000000000); // tranche tokens have 12 more decimals than
            // assets
        assertEq(vault.convertToAssets(vault.convertToShares(120000000000000000000)), 120000000000000000000);
    }

    function testAssetShareConversionWithInverseDecimals(uint64 poolId, bytes16 trancheId, uint128 assetId) public {
        vm.assume(assetId > 0);

        uint8 INVESTMENT_CURRENCY_DECIMALS = 18; // 18, like DAI
        uint8 TRANCHE_TOKEN_DECIMALS = 6; // Like USDC

        ERC20 asset = _newErc20("Currency", "CR", INVESTMENT_CURRENCY_DECIMALS);
        address vault_ = deployVault(
            poolId, TRANCHE_TOKEN_DECIMALS, defaultRestrictionSet, "", "", trancheId, assetId, address(asset)
        );
        ERC7540Vault vault = ERC7540Vault(vault_);
        TrancheTokenLike trancheToken = TrancheTokenLike(address(ERC7540Vault(vault_).share()));
        centrifugeChain.updateTrancheTokenPrice(poolId, trancheId, assetId, 1000000, uint64(block.timestamp));

        // invest
        uint256 investmentAmount = 100000000000000000000; // 100 * 10**18
        centrifugeChain.updateMember(poolId, trancheId, self, type(uint64).max);
        asset.approve(vault_, investmentAmount);
        asset.mint(self, investmentAmount);
        vault.requestDeposit(investmentAmount, self, self, "");

        // trigger executed collectInvest at a price of 1.0
        uint128 _assetId = poolManager.assetToId(address(asset)); // retrieve assetId
        uint128 shares = 100000000; // 100 * 10**6
        centrifugeChain.isFulfilledDepositRequest(
            poolId, trancheId, bytes32(bytes20(self)), _assetId, uint128(investmentAmount), shares, 0
        );
        vault.mint(shares, self);
        centrifugeChain.updateTrancheTokenPrice(
            poolId, trancheId, assetId, 1000000000000000000, uint64(block.timestamp)
        );

        // assert share/asset conversion
        assertEq(trancheToken.totalSupply(), 100000000);
        assertEq(vault.totalAssets(), 100000000000000000000);
        assertEq(vault.convertToShares(100000000000000000000), 100000000); // tranche tokens have 12 less decimals than
            // assets
        assertEq(vault.convertToAssets(vault.convertToShares(100000000000000000000)), 100000000000000000000);

        // assert share/asset conversion after price update
        centrifugeChain.updateTrancheTokenPrice(
            poolId, trancheId, assetId, 1200000000000000000, uint64(block.timestamp)
        );

        assertEq(vault.totalAssets(), 120000000000000000000);
        assertEq(vault.convertToShares(120000000000000000000), 100000000); // tranche tokens have 12 less decimals than
            // assets
        assertEq(vault.convertToAssets(vault.convertToShares(120000000000000000000)), 120000000000000000000);
    }
}
