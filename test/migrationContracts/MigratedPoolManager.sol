pragma solidity ^0.8.21;

import "src/PoolManager.sol";

// mapping(uint64 poolId => Pool) public pools;

// mapping(uint128 currencyId => address) public currencyIdToAddress;
// mapping(address => uint128 currencyId) public currencyAddressToId;

contract MigratedPoolManager is PoolManager {
    /// @dev Migrating the full state of the PoolManager requires migrated deeply nested mappings, which cannot be passed as an argument.
    /// instead we pass 3 arrays. The poolIds, the trancheIds and a uint256 array where the index is the poolId and the value is the number of tranches in that pool.
    /// This is used to reconstruct the mapping poolId => trancheId[].
    /// @param escrow_ The address of the escrow contract.
    /// @param liquidityPoolFactory_ The address of the liquidityPoolFactory contract.
    /// @param restrictionManagerFactory_ The address of the restrictionManagerFactory contract.
    /// @param trancheTokenFactory_ The address of the trancheTokenFactory contract.
    /// @param oldPoolManager The address of the old poolManager contract.
    /// @param poolIds The poolIds of the pools to migrate.
    /// @param trancheIds A sequential array of all trancheIds of all pools to migrate. Use the poolIdToTrancheIdMapping array to determine which trancheIds belongs to which poolId.
    constructor(
        address escrow_,
        address liquidityPoolFactory_,
        address restrictionManagerFactory_,
        address trancheTokenFactory_,
        address oldPoolManager,
        uint64[] memory poolIds,
        bytes16[][] memory trancheIds,
        address[][] memory allowedCurrencies,
        address[][][] memory liquidityPoolCurrencies
    ) PoolManager(escrow_, liquidityPoolFactory_, restrictionManagerFactory_, trancheTokenFactory_) {
        // migrate pools
        PoolManager oldPoolManager_ = PoolManager(oldPoolManager);
        migratePools(oldPoolManager_, poolIds, trancheIds, allowedCurrencies, liquidityPoolCurrencies);

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
        address[][][] memory liquidityPoolCurrencies
    ) internal {
        for (uint256 i = 0; i < poolIds.length; i++) {
            (uint256 createdAt) = oldPoolManager_.pools(poolIds[i]);

            Pool storage pool = pools[poolIds[i]];
            pool.createdAt = createdAt;

            // migrate tranches
            migrateTranches(poolIds[i], trancheIds[i], liquidityPoolCurrencies[i], oldPoolManager_);
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
        PoolManager oldPoolManager_
    ) internal {
        Pool storage pool = pools[poolId];
        for (uint256 j = 0; j < trancheIds.length; j++) {
            bytes16 trancheId = trancheIds[j];

            pool.tranches[trancheId].token = oldPoolManager_.getTrancheToken(poolId, trancheId);

            for (uint256 k = 0; k < liquidityPoolCurrencies[j].length; k++) {
                address currencyAddress = liquidityPoolCurrencies[j][k];
                pool.tranches[trancheId].liquidityPools[currencyAddress] =
                    oldPoolManager_.getLiquidityPool(poolId, trancheId, currencyAddress);
            }
        }
    }

    function migrateUndeployedTranches(uint64 poolId, bytes16[] memory trancheIds, PoolManager oldPoolManager_)
        internal
    {
        Pool storage pool = pools[poolId];
        for (uint256 j = 0; j < trancheIds.length; j++) {
            bytes16 trancheId = trancheIds[j];

            (uint8 decimals, string memory tokenName, string memory tokenSymbol) =
                oldPoolManager_.getUndeployedTranche(poolId, trancheId);

            undeployedTranches[poolId][trancheId].decimals = decimals;
            undeployedTranches[poolId][trancheId].tokenName = tokenName;
            undeployedTranches[poolId][trancheId].tokenSymbol = tokenSymbol;
        }
    }
}
