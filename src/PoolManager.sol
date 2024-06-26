// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import {ERC7540VaultFactory} from "src/factories/ERC7540VaultFactory.sol";
import {TrancheFactoryLike} from "src/factories/TrancheFactory.sol";
import {ITranche} from "src/interfaces/token/ITranche.sol";
import {IHook} from "src/interfaces/token/IHook.sol";
import {IERC20Metadata} from "src/interfaces/IERC20.sol";
import {Auth} from "src/Auth.sol";
import {SafeTransferLib} from "src/libraries/SafeTransferLib.sol";
import {MathLib} from "src/libraries/MathLib.sol";
import {MessagesLib} from "src/libraries/MessagesLib.sol";
import {CastLib} from "src/libraries/CastLib.sol";
import {Pool, TrancheDetails, TranchePrice, UndeployedTranche, IPoolManager} from "src/interfaces/IPoolManager.sol";
import {BytesLib} from "src/libraries/BytesLib.sol";
import {IEscrow} from "src/interfaces/IEscrow.sol";
import {IGateway} from "src/interfaces/gateway/IGateway.sol";
import {IGasService} from "src/interfaces/gateway/IGasService.sol";
import {IAuth} from "src/interfaces/IAuth.sol";

interface GasServiceLike {
    function updateGasPrice(uint256 value, uint256 computedAt) external;
    function price() external returns (uint256);
}

/// @title  Pool Manager
/// @notice This contract manages which pools & tranches exist,
///         as well as managing allowed pool currencies, and incoming and outgoing transfers.
contract PoolManager is Auth, IPoolManager {
    using BytesLib for bytes;
    using MathLib for uint256;
    using CastLib for *;

    uint8 internal constant MIN_DECIMALS = 1;
    uint8 internal constant MAX_DECIMALS = 18;

    IEscrow public immutable escrow;

    IGateway public gateway;
    address public investmentManager;
    ERC7540VaultFactory public vaultFactory;
    TrancheFactoryLike public trancheFactory;
    IGasService public gasService;

    mapping(uint64 poolId => Pool) public pools;
    mapping(address => address) public vaultToAsset;
    mapping(uint128 assetId => address) public idToAsset;
    mapping(address => uint128 assetId) public assetToId;
    mapping(uint64 poolId => mapping(bytes16 => UndeployedTranche)) public undeployedTranches;

    constructor(address escrow_, address vaultFactory_, address trancheFactory_) {
        escrow = IEscrow(escrow_);
        vaultFactory = ERC7540VaultFactory(vaultFactory_);
        trancheFactory = TrancheFactoryLike(trancheFactory_);

        wards[msg.sender] = 1;
        emit Rely(msg.sender);
    }

    // --- Administration ---
    /// @inheritdoc IPoolManager
    function file(bytes32 what, address data) external auth {
        if (what == "gateway") gateway = IGateway(data);
        else if (what == "investmentManager") investmentManager = data;
        else if (what == "trancheFactory") trancheFactory = TrancheFactoryLike(data);
        else if (what == "vaultFactory") vaultFactory = ERC7540VaultFactory(data);
        else if (what == "gasService") gasService = IGasService(data);
        else revert("PoolManager/file-unrecognized-param");
        emit File(what, data);
    }

    function recoverTokens(address token, address to, uint256 amount) external auth {
        SafeTransferLib.safeTransfer(token, to, amount);
    }

    // --- Outgoing message handling ---
    /// @inheritdoc IPoolManager
    function transfer(address asset, bytes32 recipient, uint128 amount) external {
        uint128 assetId = assetToId[asset];
        require(assetId != 0, "PoolManager/unknown-asset");

        SafeTransferLib.safeTransferFrom(asset, msg.sender, address(escrow), amount);

        gateway.send(
            abi.encodePacked(uint8(MessagesLib.Call.Transfer), assetId, msg.sender.toBytes32(), recipient, amount),
            address(this)
        );
        emit TransferCurrency(asset, recipient, amount);
    }

    /// @inheritdoc IPoolManager
    function transferTranchesToCentrifuge(uint64 poolId, bytes16 trancheId, bytes32 destinationAddress, uint128 amount)
        external
    {
        ITranche tranche = ITranche(getTranche(poolId, trancheId));
        require(address(tranche) != address(0), "PoolManager/unknown-token");

        tranche.burn(msg.sender, amount);
        gateway.send(
            abi.encodePacked(
                uint8(MessagesLib.Call.TransferTranches),
                poolId,
                trancheId,
                msg.sender.toBytes32(),
                MessagesLib.formatDomain(MessagesLib.Domain.Centrifuge),
                destinationAddress,
                amount
            ),
            address(this)
        );

        emit TransferTranchesToCentrifuge(poolId, trancheId, destinationAddress, amount);
    }

    /// @inheritdoc IPoolManager
    function transferTranchesToEVM(
        uint64 poolId,
        bytes16 trancheId,
        uint64 destinationChainId,
        address destinationAddress,
        uint128 amount
    ) external {
        ITranche tranche = ITranche(getTranche(poolId, trancheId));
        require(address(tranche) != address(0), "PoolManager/unknown-token");

        tranche.burn(msg.sender, amount);
        gateway.send(
            abi.encodePacked(
                uint8(MessagesLib.Call.TransferTranches),
                poolId,
                trancheId,
                msg.sender.toBytes32(),
                MessagesLib.formatDomain(MessagesLib.Domain.EVM, destinationChainId),
                destinationAddress.toBytes32(),
                amount
            ),
            address(this)
        );

        emit TransferTranchesToEVM(poolId, trancheId, destinationChainId, destinationAddress, amount);
    }

    // --- Incoming message handling ---
    /// @inheritdoc IPoolManager
    function handle(bytes calldata message) external auth {
        MessagesLib.Call call = MessagesLib.messageType(message);

        if (call == MessagesLib.Call.AddAsset) {
            addAsset(message.toUint128(1), message.toAddress(17));
        } else if (call == MessagesLib.Call.AddPool) {
            addPool(message.toUint64(1));
        } else if (call == MessagesLib.Call.AllowAsset) {
            allowAsset(message.toUint64(1), message.toUint128(9));
        } else if (call == MessagesLib.Call.AddTranche) {
            addTranche(
                message.toUint64(1),
                message.toBytes16(9),
                message.slice(25, 128).bytes128ToString(),
                message.toBytes32(153).toString(),
                message.toUint8(185),
                message.toAddress(186)
            );
        } else if (call == MessagesLib.Call.UpdateRestriction) {
            updateRestriction(message.toUint64(1), message.toBytes16(9), message.slice(25, message.length - 25));
        } else if (call == MessagesLib.Call.UpdateTranchePrice) {
            updateTranchePrice(
                message.toUint64(1),
                message.toBytes16(9),
                message.toUint128(25),
                message.toUint128(41),
                message.toUint64(57)
            );
        } else if (call == MessagesLib.Call.Transfer) {
            handleTransfer(message.toUint128(1), message.toAddress(49), message.toUint128(81));
        } else if (call == MessagesLib.Call.TransferTranches) {
            handleTransferTranches(
                message.toUint64(1), message.toBytes16(9), message.toAddress(66), message.toUint128(98)
            );
        } else if (call == MessagesLib.Call.UpdateTrancheMetadata) {
            updateTrancheMetadata(
                message.toUint64(1),
                message.toBytes16(9),
                message.slice(25, 128).bytes128ToString(),
                message.toBytes32(153).toString()
            );
        } else if (call == MessagesLib.Call.DisallowAsset) {
            disallowAsset(message.toUint64(1), message.toUint128(9));
        } else if (call == MessagesLib.Call.UpdateCentrifugeGasPrice) {
            updateCentrifugeGasPrice(message.toUint128(1), message.toUint256(17));
        } else {
            revert("PoolManager/invalid-message");
        }
    }

    /// @inheritdoc IPoolManager
    function addPool(uint64 poolId) public auth {
        Pool storage pool = pools[poolId];
        require(pool.createdAt == 0, "PoolManager/pool-already-added");
        pool.createdAt = block.timestamp;
        emit AddPool(poolId);
    }

    /// @inheritdoc IPoolManager
    function allowAsset(uint64 poolId, uint128 assetId) public auth {
        Pool storage pool = pools[poolId];
        require(pool.createdAt != 0, "PoolManager/invalid-pool");

        address asset = idToAsset[assetId];
        require(asset != address(0), "PoolManager/unknown-asset");

        pools[poolId].allowedAssets[asset] = true;
        emit AllowAsset(poolId, asset);
    }

    /// @inheritdoc IPoolManager
    function disallowAsset(uint64 poolId, uint128 assetId) public auth {
        Pool storage pool = pools[poolId];
        require(pool.createdAt != 0, "PoolManager/invalid-pool");

        address asset = idToAsset[assetId];
        require(asset != address(0), "PoolManager/unknown-asset");

        pools[poolId].allowedAssets[asset] = false;
        emit DisallowAsset(poolId, asset);
    }

    /// @inheritdoc IPoolManager
    function addTranche(
        uint64 poolId,
        bytes16 trancheId,
        string memory name,
        string memory symbol,
        uint8 decimals,
        address hook
    ) public auth {
        require(decimals >= MIN_DECIMALS, "PoolManager/too-few-tranche-token-decimals");
        require(decimals <= MAX_DECIMALS, "PoolManager/too-many-tranche-token-decimals");

        Pool storage pool = pools[poolId];
        require(pool.createdAt != 0, "PoolManager/invalid-pool");

        UndeployedTranche storage undeployedTranche = undeployedTranches[poolId][trancheId];
        require(undeployedTranche.decimals == 0, "PoolManager/tranche-already-exists");
        require(getTranche(poolId, trancheId) == address(0), "PoolManager/tranche-already-deployed");

        // Hook can be address zero if the tranche token is fully permissionless and has no custom logic
        require(
            hook == address(0) || IHook(hook).supportsInterface(type(IHook).interfaceId) == true,
            "PoolManager/invalid-hook"
        );

        undeployedTranche.decimals = decimals;
        undeployedTranche.tokenName = name;
        undeployedTranche.tokenSymbol = symbol;
        undeployedTranche.hook = hook;

        emit AddTranche(poolId, trancheId);
    }

    /// @inheritdoc IPoolManager
    function updateTrancheMetadata(uint64 poolId, bytes16 trancheId, string memory name, string memory symbol)
        public
        auth
    {
        ITranche tranche = ITranche(getTranche(poolId, trancheId));
        require(address(tranche) != address(0), "PoolManager/unknown-token");

        require(
            keccak256(bytes(tranche.name())) != keccak256(bytes(name))
                || keccak256(bytes(tranche.symbol())) != keccak256(bytes(symbol)),
            "PoolManager/old-metadata"
        );

        tranche.file("name", name);
        tranche.file("symbol", symbol);
    }

    /// @inheritdoc IPoolManager
    function updateTranchePrice(uint64 poolId, bytes16 trancheId, uint128 assetId, uint128 price, uint64 computedAt)
        public
        auth
    {
        TrancheDetails storage tranche = pools[poolId].tranches[trancheId];
        require(tranche.token != address(0), "PoolManager/tranche-does-not-exist");

        address asset = idToAsset[assetId];
        require(computedAt >= tranche.prices[asset].computedAt, "PoolManager/cannot-set-older-price");

        tranche.prices[asset] = TranchePrice(price, computedAt);
        emit PriceUpdate(poolId, trancheId, asset, price, computedAt);
    }

    /// @inheritdoc IPoolManager
    function updateRestriction(uint64 poolId, bytes16 trancheId, bytes memory update) public auth {
        ITranche tranche = ITranche(getTranche(poolId, trancheId));
        require(address(tranche) != address(0), "PoolManager/unknown-token");
        IHook(tranche.hook()).updateRestriction(address(tranche), update);
    }

    /// @inheritdoc IPoolManager
    function addAsset(uint128 assetId, address asset) public auth {
        // Currency index on the Centrifuge side should start at 1
        require(assetId != 0, "PoolManager/asset-id-has-to-be-greater-than-0");
        require(idToAsset[assetId] == address(0), "PoolManager/asset-id-in-use");
        require(assetToId[asset] == 0, "PoolManager/asset-address-in-use");

        uint8 assetDecimals = IERC20Metadata(asset).decimals();
        require(assetDecimals >= MIN_DECIMALS, "PoolManager/too-few-asset-decimals");
        require(assetDecimals <= MAX_DECIMALS, "PoolManager/too-many-asset-decimals");

        idToAsset[assetId] = asset;
        assetToId[asset] = assetId;

        // Give investment manager infinite approval for asset
        // in the escrow to transfer to the user on redeem or withdraw
        escrow.approveMax(asset, investmentManager);

        // Give pool manager infinite approval for asset
        // in the escrow to transfer to the user on transfer
        escrow.approveMax(asset, address(this));

        emit AddAsset(assetId, asset);
    }

    /// @inheritdoc IPoolManager
    function handleTransfer(uint128 assetId, address recipient, uint128 amount) public auth {
        address asset = idToAsset[assetId];
        require(asset != address(0), "PoolManager/unknown-asset");

        SafeTransferLib.safeTransferFrom(asset, address(escrow), recipient, amount);
    }

    /// @inheritdoc IPoolManager
    function handleTransferTranches(uint64 poolId, bytes16 trancheId, address destinationAddress, uint128 amount)
        public
        auth
    {
        ITranche tranche = ITranche(getTranche(poolId, trancheId));
        require(address(tranche) != address(0), "PoolManager/unknown-token");

        tranche.mint(destinationAddress, amount);
    }

    /// @inheritdoc IPoolManager
    function updateCentrifugeGasPrice(uint128 price, uint256 computedAt) public auth {
        require(price > 0, "PoolManager/price-cannot-be-zero");
        require(gasService.gasPrice() != price, "PoolManager/same-price-already-set");
        gasService.updateGasPrice(price, computedAt);
    }

    // --- Public functions ---
    // slither-disable-start reentrancy-eth
    /// @inheritdoc IPoolManager
    function deployTranche(uint64 poolId, bytes16 trancheId) public returns (address) {
        UndeployedTranche storage undeployedTranche = undeployedTranches[poolId][trancheId];
        require(undeployedTranche.decimals != 0, "PoolManager/tranche-not-added");

        address[] memory trancheWards = new address[](2);
        trancheWards[0] = investmentManager;
        trancheWards[1] = address(this);

        address token = trancheFactory.newTranche(
            poolId,
            trancheId,
            undeployedTranche.tokenName,
            undeployedTranche.tokenSymbol,
            undeployedTranche.decimals,
            trancheWards
        );

        if (undeployedTranche.hook != address(0)) {
            ITranche(token).file("hook", undeployedTranche.hook);
        }

        pools[poolId].tranches[trancheId].token = token;

        delete undeployedTranches[poolId][trancheId];

        // Give investment manager infinite approval for tranche tokens
        // in the escrow to transfer to the user on deposit or mint
        escrow.approveMax(token, investmentManager);

        emit DeployTranche(poolId, trancheId, token);
        return token;
    }
    // slither-disable-end reentrancy-eth

    /// @inheritdoc IPoolManager
    function deployVault(uint64 poolId, bytes16 trancheId, address asset) public returns (address) {
        TrancheDetails storage tranche = pools[poolId].tranches[trancheId];
        require(tranche.token != address(0), "PoolManager/tranche-does-not-exist");
        require(isAllowedAsset(poolId, asset), "PoolManager/asset-not-supported");

        address vault = ITranche(tranche.token).vault(asset);
        require(vault == address(0), "PoolManager/vault-already-deployed");

        // Rely investment manager on vault so it can mint tokens
        address[] memory vaultWards = new address[](1);
        vaultWards[0] = investmentManager;

        // Deploy vault
        vault = vaultFactory.newVault(
            poolId, trancheId, asset, tranche.token, address(escrow), investmentManager, vaultWards
        );
        vaultToAsset[vault] = asset;

        // Link vault to tranche token
        IAuth(tranche.token).rely(vault);
        ITranche(tranche.token).updateVault(asset, vault);

        emit DeployVault(poolId, trancheId, asset, vault);
        return vault;
    }

    /// @inheritdoc IPoolManager
    function removeVault(uint64 poolId, bytes16 trancheId, address asset) public auth {
        require(pools[poolId].createdAt != 0, "PoolManager/pool-does-not-exist");
        TrancheDetails storage tranche = pools[poolId].tranches[trancheId];
        require(tranche.token != address(0), "PoolManager/tranche-does-not-exist");

        address vault = ITranche(tranche.token).vault(asset);
        require(vault != address(0), "PoolManager/vault-not-deployed");

        vaultFactory.denyVault(vault, investmentManager);

        IAuth(tranche.token).deny(vault);
        ITranche(tranche.token).updateVault(asset, address(0));

        emit RemoveVault(poolId, trancheId, asset, vault);
    }

    // --- Helpers ---
    /// @inheritdoc IPoolManager
    function getTranche(uint64 poolId, bytes16 trancheId) public view returns (address) {
        TrancheDetails storage tranche = pools[poolId].tranches[trancheId];
        return tranche.token;
    }

    /// @inheritdoc IPoolManager
    function getTranchePrice(uint64 poolId, bytes16 trancheId, address asset)
        public
        view
        returns (uint128 price, uint64 computedAt)
    {
        TranchePrice memory value = pools[poolId].tranches[trancheId].prices[asset];
        price = value.price;
        computedAt = value.computedAt;
    }

    /// @inheritdoc IPoolManager
    function getVault(uint64 poolId, bytes16 trancheId, uint128 assetId) public view returns (address) {
        return ITranche(pools[poolId].tranches[trancheId].token).vault(idToAsset[assetId]);
    }

    /// @inheritdoc IPoolManager
    function getVault(uint64 poolId, bytes16 trancheId, address asset) public view returns (address) {
        return ITranche(pools[poolId].tranches[trancheId].token).vault(asset);
    }

    /// @inheritdoc IPoolManager
    function getVaultAsset(address vault) public view override returns (address asset) {
        asset = vaultToAsset[vault];
        require(asset != address(0), "PoolManager/unknown-vault");
    }

    /// @inheritdoc IPoolManager
    function isAllowedAsset(uint64 poolId, address asset) public view returns (bool) {
        return pools[poolId].allowedAssets[asset];
    }
}
