// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

/// @dev Centrifuge pools
struct Pool {
    uint256 createdAt;
    mapping(bytes16 trancheId => Tranche) tranches;
    mapping(address currency => bool) allowedCurrencies;
}

/// @dev Each Centrifuge pool is associated to 1 or more tranches
struct Tranche {
    address token;
    /// @dev Each tranche can have multiple liquidity pools deployed,
    ///      each linked to a unique investment currency (asset)
    mapping(address currency => address liquidityPool) liquidityPools;
    /// @dev Each tranche has a price per liquidity pool
    mapping(address liquidityPool => TrancheTokenPrice) prices;
}

struct TrancheTokenPrice {
    uint256 price;
    uint64 computedAt;
}

/// @dev Temporary storage that is only present between addTranche and deployTranche
struct UndeployedTranche {
    /// @dev The decimals of the leading pool currency. Liquidity Pool shareshave
    ///      to be denomatimated with the same precision.
    uint8 decimals;
    /// @dev Metadata of the to be deployed erc20 token
    string tokenName;
    string tokenSymbol;
    /// @dev Identifier of the restriction set that applies to this tranche token
    uint8 restrictionSet;
}

contract IPoolManager {
    // --- Events ---
    event File(bytes32 indexed what, address data);
    event AddCurrency(uint128 indexed currencyId, address indexed currency);
    event AddPool(uint64 indexed poolId);
    event AllowInvestmentCurrency(uint64 indexed poolId, address indexed currency);
    event DisallowInvestmentCurrency(uint64 indexed poolId, address indexed currency);
    event AddTranche(uint64 indexed poolId, bytes16 indexed trancheId);
    event DeployTranche(uint64 indexed poolId, bytes16 indexed trancheId, address indexed trancheToken);
    event DeployLiquidityPool(
        uint64 indexed poolId, bytes16 indexed trancheId, address indexed currency, address liquidityPool
    );
    event RemoveLiquidityPool(
        uint64 indexed poolId, bytes16 indexed trancheId, address indexed currency, address liquidityPool
    );
    event PriceUpdate(
        uint64 indexed poolId, bytes16 indexed trancheId, address indexed currency, uint256 price, uint64 computedAt
    );
    event TransferCurrency(address indexed currency, bytes32 indexed recipient, uint128 amount);
    event TransferTrancheTokensToCentrifuge(
        uint64 indexed poolId, bytes16 indexed trancheId, bytes32 destinationAddress, uint128 amount
    );
    event TransferTrancheTokensToEVM(
        uint64 indexed poolId,
        bytes16 indexed trancheId,
        uint64 indexed destinationChainId,
        address destinationAddress,
        uint128 amount
    );
}
