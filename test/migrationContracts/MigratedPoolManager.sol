import "src/PoolManager.sol";

// mapping(uint64 poolId => Pool) public pools;

// /// @dev Chain agnostic currency id -> evm currency address and reverse mapping
// mapping(uint128 currencyId => address) public currencyIdToAddress;
// mapping(address => uint128 currencyId) public currencyAddressToId;

contract MigratedPoolManager is PoolManager {
    uint8 internal constant MAX_DECIMALS = 18;

    constructor(
        address escrow_,
        address liquidityPoolFactory_,
        address restrictionManagerFactory_,
        address trancheTokenFactory_,
        address oldPoolManager,
        uint64[] memory poolIds
    ) PoolManager(escrow_, liquidityPoolFactory_, restrictionManagerFactory_, trancheTokenFactory_) {
        // migrate pools
        for(uint256 i = 0; i < poolIds.length; i++) {
            uint64 poolId = poolIds[i];
            PoolManager oldPoolManager_ = PoolManager(oldPoolManager);
            Pool memory pool = oldPoolManager_.pools(poolId);
            pools[poolId] = pool;
            
            address currencyAddress = oldPoolManager_.currencyIdToAddress(pool.currencyId);
            currencyIdToAddress[pool.currencyId] = currencyAddress;
            currencyAddressToId[currencyAddress] = pool.currencyId;
        }
    }
}
