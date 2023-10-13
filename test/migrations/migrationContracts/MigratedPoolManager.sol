// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.21;

import "src/PoolManager.sol";
import "forge-std/console.sol";

contract MigratedPoolManager is PoolManager {
    /// @param poolIds The poolIds of the pools to migrate.
    /// @param trancheIds The trancheIds of the tranches to migrate, arranged as arrays of trancheIds for each pool.
    /// @param allowedCurrencies The allowed currencies of the pools to migrate, arranged as arrays of allowed
    /// currencies for each pool.
    /// @param liquidityPoolCurrencies The liquidity pool currencies of the tranches to migrate, arranged as arrays of
    /// liquidity pool currencies for each tranche of each pool.
    constructor(
        address escrow_,
        address liquidityPoolFactory_,
        address restrictionManagerFactory_,
        address trancheTokenFactory_,
        address oldPoolManager,
        uint64[] memory poolIds,
        bytes16[][] memory trancheIds,
        address[][] memory allowedCurrencies,
        address[][][] memory liquidityPoolCurrencies,
        address[][][] memory liquidityPoolOverrides
    ) PoolManager(escrow_, liquidityPoolFactory_, restrictionManagerFactory_, trancheTokenFactory_) {
        // migrate pools
        PoolManager oldPoolManager_ = PoolManager(oldPoolManager);
        migratePools(
            oldPoolManager_, poolIds, trancheIds, allowedCurrencies, liquidityPoolCurrencies, liquidityPoolOverrides
        );

        for (uint256 i = 0; i < allowedCurrencies.length; i++) {
            for (uint256 j = 0; j < allowedCurrencies[i].length; j++) {
                address currencyAddress = allowedCurrencies[i][j];
                uint128 currencyId = oldPoolManager_.currencyAddressToId(currencyAddress);
                currencyAddressToId[currencyAddress] = currencyId;
                currencyIdToAddress[currencyId] = currencyAddress;
            }
        }
    }

    function migratePools(
        PoolManager oldPoolManager_,
        uint64[] memory poolIds,
        bytes16[][] memory trancheIds,
        address[][] memory allowedCurrencies,
        address[][][] memory liquidityPoolCurrencies,
        address[][][] memory liquidityPoolOverrides
    ) internal {
        for (uint256 i = 0; i < poolIds.length; i++) {
            (uint256 createdAt) = oldPoolManager_.pools(poolIds[i]);
            Pool storage pool = pools[poolIds[i]];
            pool.createdAt = createdAt;
            address[][] memory liquidityPoolOverrides_ =
                liquidityPoolOverrides.length > 0 ? liquidityPoolOverrides[i] : new address[][](0);

            // migrate tranches
            migrateTranches(
                poolIds[i], trancheIds[i], liquidityPoolCurrencies[i], oldPoolManager_, liquidityPoolOverrides_
            );
            migrateUndeployedTranches(poolIds[i], trancheIds[i], oldPoolManager_);

            // migrate allowed currencies
            for (uint256 j = 0; j < allowedCurrencies[i].length; j++) {
                address currencyAddress = allowedCurrencies[i][j];
                pool.allowedCurrencies[currencyAddress] = true;
            }
        }
    }

    function migrateTranches(
        uint64 poolId,
        bytes16[] memory trancheIds,
        address[][] memory liquidityPoolCurrencies,
        PoolManager oldPoolManager_,
        address[][] memory liquidityPoolOverrides
    ) internal {
        Pool storage pool = pools[poolId];
        for (uint256 j = 0; j < trancheIds.length; j++) {
            address[] memory liquidityPoolOverrides_ =
                liquidityPoolOverrides.length > 0 ? liquidityPoolOverrides[j] : new address[](0);
            bytes16 trancheId = trancheIds[j];
            pool.tranches[trancheId].token = oldPoolManager_.getTrancheToken(poolId, trancheId);
            for (uint256 k = 0; k < liquidityPoolCurrencies[j].length; k++) {
                address currencyAddress = liquidityPoolCurrencies[j][k];
                if (liquidityPoolOverrides_.length > 0) {
                    pool.tranches[trancheId].liquidityPools[currencyAddress] = liquidityPoolOverrides[j][k];
                } else {
                    pool.tranches[trancheId].liquidityPools[currencyAddress] =
                        oldPoolManager_.getLiquidityPool(poolId, trancheId, currencyAddress);
                }
            }
        }
    }

    function migrateUndeployedTranches(uint64 poolId, bytes16[] memory trancheIds, PoolManager oldPoolManager_)
        internal
    {
        for (uint256 j = 0; j < trancheIds.length; j++) {
            bytes16 trancheId = trancheIds[j];
            (uint8 decimals, string memory tokenName, string memory tokenSymbol) =
                oldPoolManager_.undeployedTranches(poolId, trancheId);
            undeployedTranches[poolId][trancheId].decimals = decimals;
            undeployedTranches[poolId][trancheId].tokenName = tokenName;
            undeployedTranches[poolId][trancheId].tokenSymbol = tokenSymbol;
        }
    }
}
