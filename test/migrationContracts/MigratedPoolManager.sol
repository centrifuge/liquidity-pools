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
        address[][] memory allowedCurrencies
    ) PoolManager(escrow_, liquidityPoolFactory_, restrictionManagerFactory_, trancheTokenFactory_) {
        // migrate pools
        for (uint256 i = 0; i < poolIds.length; i++) {
            PoolManager oldPoolManager_ = PoolManager(oldPoolManager);
            (, uint256 createdAt) = oldPoolManager_.pools(poolIds[i]);

            Pool storage pool = pools[poolIds[i]];
            pool.poolId = poolIds[i];
            pool.createdAt = createdAt;

            // migrate tranches
            for (uint256 j = 0; j < trancheIds[i].length; j++) {
                bytes16 trancheId = trancheIds[i][j];

                (address token, uint8 decimals, uint256 createdAt, string memory tokenName, string memory tokenSymbol) =
                    oldPoolManager_.getTranche(poolIds[i], trancheId);

                pool.tranches[trancheId].token = token;
                pool.tranches[trancheId].decimals = decimals;
                pool.tranches[trancheId].createdAt = createdAt;
                pool.tranches[trancheId].tokenName = tokenName;
                pool.tranches[trancheId].tokenSymbol = tokenSymbol;

                // (, uint256 maturityDate, uint256 totalSupply, uint256 totalRedeemable) = oldPoolManager.tranches(poolIds[i], trancheId);
                // tranche.trancheId = trancheId;
                // tranche.maturityDate = maturityDate;
                // tranche.totalSupply = totalSupply;
                // tranche.totalRedeemable = totalRedeemable;
            }

            // migrate allowed currencies
            for (uint256 j = 0; j < allowedCurrencies[i].length; j++) {
                address currencyAddress = allowedCurrencies[i][j];
                pool.allowedCurrencies[currencyAddress] = true;
            }

            // address currencyAddress = oldPoolManager_.currencyIdToAddress(pool.currencyId);
            // currencyIdToAddress[pool.currencyId] = currencyAddress;
            // currencyAddressToId[currencyAddress] = pool.currencyId;
        }
    }
}
