// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.5.0;

/// @dev Centrifuge pools
struct Pool {
    uint256 createdAt;
    mapping(bytes16 trancheId => Tranche) tranches;
    mapping(address asset => bool) allowedCurrencies;
}

/// @dev Each Centrifuge pool is associated to 1 or more tranches
struct Tranche {
    address token;
    /// @dev Each tranche can have multiple vaults deployed,
    ///      each linked to a unique asset
    mapping(address asset => address vault) vaults;
    /// @dev Each tranche has a price per vault
    mapping(address vault => TrancheTokenPrice) prices;
}

struct TrancheTokenPrice {
    uint128 price;
    uint64 computedAt;
}

/// @dev Temporary storage that is only present between addTranche and deployTranche
struct UndeployedTranche {
    /// @dev The decimals of the leading pool asset. Vault shares have
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
    event AddAsset(uint128 indexed assetId, address indexed asset);
    event AddPool(uint64 indexed poolId);
    event AllowAsset(uint64 indexed poolId, address indexed asset);
    event DisallowAsset(uint64 indexed poolId, address indexed asset);
    event AddTranche(uint64 indexed poolId, bytes16 indexed trancheId);
    event DeployTranche(uint64 indexed poolId, bytes16 indexed trancheId, address indexed trancheToken);
    event DeployVault(uint64 indexed poolId, bytes16 indexed trancheId, address indexed asset, address vault);
    event RemoveVault(uint64 indexed poolId, bytes16 indexed trancheId, address indexed asset, address vault);
    event PriceUpdate(
        uint64 indexed poolId, bytes16 indexed trancheId, address indexed asset, uint256 price, uint64 computedAt
    );
    event TransferCurrency(address indexed asset, bytes32 indexed recipient, uint128 amount);
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
    function idToAsset(uint128 assetId) external view returns (address asset);

    /// @notice TODO
    function assetToId(address) external view returns (uint128 assetId);

    /// @notice TODO
    function file(bytes32 what, address data) external;

    /// @notice TODO
    function transfer(address asset, bytes32 recipient, uint128 amount) external;

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
    ///             a new supported asset to the pool details.
    ///             Adding new currencies allow the creation of new vaults for the underlying Centrifuge pool.
    /// @dev        The function can only be executed by the gateway contract.
    function allowAsset(uint64 poolId, uint128 assetId) external;

    /// @notice TODO
    function disallowAsset(uint64 poolId, uint128 assetId) external;

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
        uint128 assetId,
        uint128 price,
        uint64 computedAt
    ) external;

    /// @notice TODO
    function updateMember(uint64 poolId, bytes16 trancheId, address user, uint64 validUntil) external;

    /// @notice TODO
    function freeze(uint64 poolId, bytes16 trancheId, address user) external;

    /// @notice TODO
    function unfreeze(uint64 poolId, bytes16 trancheId, address user) external;

    /// @notice A global chain agnostic asset index is maintained on Centrifuge. This function maps
    ///         a asset from the Centrifuge index to its corresponding address on the evm chain.
    ///         The chain agnostic asset id has to be used to pass asset information to the Centrifuge.
    /// @dev    This function can only be executed by the gateway contract.
    function addAsset(uint128 assetId, address asset) external;

    /// @notice TODO
    function handle(bytes calldata message) external;

    /// @notice TODO
    function handleTransfer(uint128 assetId, address recipient, uint128 amount) external;

    /// @notice TODO
    function handleTransferTrancheTokens(uint64 poolId, bytes16 trancheId, address destinationAddress, uint128 amount)
        external;

    /// @notice TODO
    function deployTranche(uint64 poolId, bytes16 trancheId) external returns (address);

    /// @notice TODO
    function deployVault(uint64 poolId, bytes16 trancheId, address asset) external returns (address);

    /// @notice TODO
    function removeVault(uint64 poolId, bytes16 trancheId, address asset) external;

    /// @notice TODO
    function updateCentrifugeTokenPrice(uint256 price) external;

    /// @notice TODO
    function getTrancheToken(uint64 poolId, bytes16 trancheId) external view returns (address);

    /// @notice TODO
    function getVault(uint64 poolId, bytes16 trancheId, uint128 assetId) external view returns (address);

    /// @notice TODO
    function getVault(uint64 poolId, bytes16 trancheId, address asset) external view returns (address);

    /// @notice TODO
    function getTrancheTokenPrice(uint64 poolId, bytes16 trancheId, address asset)
        external
        view
        returns (uint128 price, uint64 computedAt);

    /// @notice TODO
    function isAllowedAsset(uint64 poolId, address asset) external view returns (bool);
}
