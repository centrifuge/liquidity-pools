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
    uint128 price;
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

interface IPoolManager {
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

    /// @notice TODO
    function currencyIdToAddress(uint128 currencyId) external view returns (address currency);

    /// @notice TODO
    function currencyAddressToId(address) external view returns (uint128 currencyId);

    /// @notice TODO
    function file(bytes32 what, address data) external;

    /// @notice TODO
    function transfer(address currency, bytes32 recipient, uint128 amount) external;

    /// @notice TODO
    function transferTrancheTokensToCentrifuge(
        uint64 poolId,
        bytes16 trancheId,
        bytes32 destinationAddress,
        uint128 amount
    ) external;

    /// @notice TODO
    function transferTrancheTokensToEVM(
        uint64 poolId,
        bytes16 trancheId,
        uint64 destinationChainId,
        address destinationAddress,
        uint128 amount
    ) external;

    /// @notice    New pool details from an existing Centrifuge pool are added.
    /// @dev       The function can only be executed by the gateway contract.
    function addPool(uint64 poolId) external;

    /// @notice     Centrifuge pools can support multiple currencies for investing. this function adds
    ///             a new supported currency to the pool details.
    ///             Adding new currencies allow the creation of new liquidity pools for the underlying Centrifuge pool.
    /// @dev        The function can only be executed by the gateway contract.
    function allowInvestmentCurrency(uint64 poolId, uint128 currencyId) external;

    /// @notice TODO
    function disallowInvestmentCurrency(uint64 poolId, uint128 currencyId) external;

    /// @notice     New tranche details from an existing Centrifuge pool are added.
    /// @dev        The function can only be executed by the gateway contract.
    function addTranche(
        uint64 poolId,
        bytes16 trancheId,
        string memory tokenName,
        string memory tokenSymbol,
        uint8 decimals,
        uint8 restrictionSet
    ) external;

    /// @notice TODO
    function updateTrancheTokenMetadata(
        uint64 poolId,
        bytes16 trancheId,
        string memory tokenName,
        string memory tokenSymbol
    ) external;

    /// @notice TODO
    function updateTrancheTokenPrice(
        uint64 poolId,
        bytes16 trancheId,
        uint128 currencyId,
        uint128 price,
        uint64 computedAt
    ) external;

    /// @notice TODO
    function updateMember(uint64 poolId, bytes16 trancheId, address user, uint64 validUntil) external;

    /// @notice TODO
    function freeze(uint64 poolId, bytes16 trancheId, address user) external;

    /// @notice TODO
    function unfreeze(uint64 poolId, bytes16 trancheId, address user) external;

    /// @notice A global chain agnostic currency index is maintained on Centrifuge. This function maps
    ///         a currency from the Centrifuge index to its corresponding address on the evm chain.
    ///         The chain agnostic currency id has to be used to pass currency information to the Centrifuge.
    /// @dev    This function can only be executed by the gateway contract.
    function addCurrency(uint128 currencyId, address currency) external;

    /// @notice TODO
    function handle(bytes calldata message) external;

    /// @notice TODO
    function handleTransfer(uint128 currencyId, address recipient, uint128 amount) external;

    /// @notice TODO
    function handleTransferTrancheTokens(uint64 poolId, bytes16 trancheId, address destinationAddress, uint128 amount)
        external;

    /// @notice TODO
    function deployTranche(uint64 poolId, bytes16 trancheId) external returns (address);

    /// @notice TODO
    function deployLiquidityPool(uint64 poolId, bytes16 trancheId, address currency) external returns (address);

    /// @notice TODO
    function removeLiquidityPool(uint64 poolId, bytes16 trancheId, address currency) external;

    /// @notice TODO
    function getTrancheToken(uint64 poolId, bytes16 trancheId) external view returns (address);

    /// @notice TODO
    function getLiquidityPool(uint64 poolId, bytes16 trancheId, uint128 currencyId) external view returns (address);

    /// @notice TODO
    function getLiquidityPool(uint64 poolId, bytes16 trancheId, address currency) external view returns (address);

    /// @notice TODO
    function getTrancheTokenPrice(uint64 poolId, bytes16 trancheId, address currency)
        external
        view
        returns (uint128 price, uint64 computedAt);

    /// @notice TODO
    function isAllowedAsInvestmentCurrency(uint64 poolId, address currency) external view returns (bool);
}
