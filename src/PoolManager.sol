// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import {ERC7540VaultFactory} from "src/factories/ERC7540VaultFactory.sol";
import {RestrictionManagerFactoryLike} from "src/factories/RestrictionManagerFactory.sol";
import {TrancheTokenFactoryLike} from "src/factories/TrancheTokenFactory.sol";
import {TrancheTokenLike} from "src/token/Tranche.sol";
import {RestrictionManagerLike} from "src/token/RestrictionManager.sol";
import {IERC20Metadata} from "src/interfaces/IERC20.sol";
import {Auth} from "src/Auth.sol";
import {SafeTransferLib} from "src/libraries/SafeTransferLib.sol";
import {MathLib} from "src/libraries/MathLib.sol";
import {MessagesLib} from "src/libraries/MessagesLib.sol";
import {CastLib} from "src/libraries/CastLib.sol";
import {Pool, Tranche, TrancheTokenPrice, UndeployedTranche, IPoolManager} from "src/interfaces/IPoolManager.sol";
import {BytesLib} from "src/libraries/BytesLib.sol";
import {IEscrow} from "src/interfaces/IEscrow.sol";

interface GatewayLike {
    function send(bytes memory message, address source) external;
}

interface InvestmentManagerLike {
    function vaults(uint64 poolId, bytes16 trancheId, address asset) external returns (address);
    function getTrancheToken(uint64 _poolId, bytes16 _trancheId) external view returns (address);
}

interface AuthLike {
    function rely(address user) external;
    function deny(address user) external;
}

interface GasServiceLike {
    function updateGasPrice(uint256 value) external;
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

    GatewayLike public gateway;
    ERC7540VaultFactory public vaultFactory;
    InvestmentManagerLike public investmentManager;
    TrancheTokenFactoryLike public trancheTokenFactory;
    RestrictionManagerFactoryLike public restrictionManagerFactory;
    GasServiceLike public gasService;

    mapping(uint64 poolId => Pool) public pools;
    mapping(address => address) public vaultToAsset;
    mapping(uint128 assetId => address) public idToAsset;
    mapping(address => uint128 assetId) public assetToId;
    mapping(uint64 poolId => mapping(bytes16 => UndeployedTranche)) public undeployedTranches;

    constructor(
        address escrow_,
        address vaultFactory_,
        address restrictionManagerFactory_,
        address trancheTokenFactory_
    ) {
        escrow = IEscrow(escrow_);
        vaultFactory = ERC7540VaultFactory(vaultFactory_);
        restrictionManagerFactory = RestrictionManagerFactoryLike(restrictionManagerFactory_);
        trancheTokenFactory = TrancheTokenFactoryLike(trancheTokenFactory_);

        wards[msg.sender] = 1;
        emit Rely(msg.sender);
    }

    // --- Administration ---
    /// @inheritdoc IPoolManager
    function file(bytes32 what, address data) external auth {
        if (what == "gateway") gateway = GatewayLike(data);
        else if (what == "investmentManager") investmentManager = InvestmentManagerLike(data);
        else if (what == "trancheTokenFactory") trancheTokenFactory = TrancheTokenFactoryLike(data);
        else if (what == "vaultFactory") vaultFactory = ERC7540VaultFactory(data);
        else if (what == "restrictionManagerFactory") restrictionManagerFactory = RestrictionManagerFactoryLike(data);
        else if (what == "gasService") gasService = GasServiceLike(data);
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
            abi.encodePacked(uint8(MessagesLib.Call.Transfer), assetId, msg.sender, recipient, amount), address(this)
        );
        emit TransferCurrency(asset, recipient, amount);
    }

    /// @inheritdoc IPoolManager
    function transferTrancheTokensToCentrifuge(
        uint64 poolId,
        bytes16 trancheId,
        bytes32 destinationAddress,
        uint128 amount
    ) external {
        TrancheTokenLike trancheToken = TrancheTokenLike(getTrancheToken(poolId, trancheId));
        require(address(trancheToken) != address(0), "PoolManager/unknown-token");

        trancheToken.burn(msg.sender, amount);
        gateway.send(
            abi.encodePacked(
                uint8(MessagesLib.Call.TransferTrancheTokens),
                poolId,
                trancheId,
                msg.sender.toBytes32(),
                MessagesLib.formatDomain(MessagesLib.Domain.Centrifuge),
                destinationAddress,
                amount
            ),
            address(this)
        );

        emit TransferTrancheTokensToCentrifuge(poolId, trancheId, destinationAddress, amount);
    }

    /// @inheritdoc IPoolManager
    function transferTrancheTokensToEVM(
        uint64 poolId,
        bytes16 trancheId,
        uint64 destinationChainId,
        address destinationAddress,
        uint128 amount
    ) external {
        TrancheTokenLike trancheToken = TrancheTokenLike(getTrancheToken(poolId, trancheId));
        require(address(trancheToken) != address(0), "PoolManager/unknown-token");

        trancheToken.burn(msg.sender, amount);
        gateway.send(
            abi.encodePacked(
                uint8(MessagesLib.Call.TransferTrancheTokens),
                poolId,
                trancheId,
                msg.sender,
                MessagesLib.formatDomain(MessagesLib.Domain.EVM, destinationChainId),
                destinationAddress.toBytes32(),
                amount
            ),
            address(this)
        );

        emit TransferTrancheTokensToEVM(poolId, trancheId, destinationChainId, destinationAddress, amount);
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
                message.toUint8(186)
            );
        } else if (call == MessagesLib.Call.UpdateMember) {
            updateMember(message.toUint64(1), message.toBytes16(9), message.toAddress(25), message.toUint64(57));
        } else if (call == MessagesLib.Call.UpdateTrancheTokenPrice) {
            updateTrancheTokenPrice(
                message.toUint64(1),
                message.toBytes16(9),
                message.toUint128(25),
                message.toUint128(41),
                message.toUint64(57)
            );
        } else if (call == MessagesLib.Call.Transfer) {
            handleTransfer(message.toUint128(1), message.toAddress(49), message.toUint128(81));
        } else if (call == MessagesLib.Call.TransferTrancheTokens) {
            handleTransferTrancheTokens(
                message.toUint64(1), message.toBytes16(9), message.toAddress(66), message.toUint128(98)
            );
        } else if (call == MessagesLib.Call.UpdateTrancheTokenMetadata) {
            updateTrancheTokenMetadata(
                message.toUint64(1),
                message.toBytes16(9),
                message.slice(25, 128).bytes128ToString(),
                message.toBytes32(153).toString()
            );
        } else if (call == MessagesLib.Call.Freeze) {
            freeze(message.toUint64(1), message.toBytes16(9), message.toAddress(25));
        } else if (call == MessagesLib.Call.Unfreeze) {
            unfreeze(message.toUint64(1), message.toBytes16(9), message.toAddress(25));
        } else if (call == MessagesLib.Call.DisallowAsset) {
            disallowAsset(message.toUint64(1), message.toUint128(9));
        } else if (call == MessagesLib.Call.UpdateCentrifugeGasPrice) {
            updateCentrifugeGasPrice(message.toUint256(1));
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

        pools[poolId].allowedCurrencies[asset] = true;
        emit AllowAsset(poolId, asset);
    }

    /// @inheritdoc IPoolManager
    function disallowAsset(uint64 poolId, uint128 assetId) public auth {
        Pool storage pool = pools[poolId];
        require(pool.createdAt != 0, "PoolManager/invalid-pool");

        address asset = idToAsset[assetId];
        require(asset != address(0), "PoolManager/unknown-asset");

        pools[poolId].allowedCurrencies[asset] = false;
        emit DisallowAsset(poolId, asset);
    }

    /// @inheritdoc IPoolManager
    function addTranche(
        uint64 poolId,
        bytes16 trancheId,
        string memory name,
        string memory symbol,
        uint8 decimals,
        uint8 restrictionSet
    ) public auth {
        require(decimals >= MIN_DECIMALS, "PoolManager/too-few-tranche-token-decimals");
        require(decimals <= MAX_DECIMALS, "PoolManager/too-many-tranche-token-decimals");

        Pool storage pool = pools[poolId];
        require(pool.createdAt != 0, "PoolManager/invalid-pool");

        UndeployedTranche storage undeployedTranche = undeployedTranches[poolId][trancheId];
        require(undeployedTranche.decimals == 0, "PoolManager/tranche-already-exists");
        require(getTrancheToken(poolId, trancheId) == address(0), "PoolManager/tranche-already-deployed");

        undeployedTranche.decimals = decimals;
        undeployedTranche.tokenName = name;
        undeployedTranche.tokenSymbol = symbol;
        undeployedTranche.restrictionSet = restrictionSet;

        emit AddTranche(poolId, trancheId);
    }

    /// @inheritdoc IPoolManager
    function updateTrancheTokenMetadata(uint64 poolId, bytes16 trancheId, string memory name, string memory symbol)
        public
        auth
    {
        TrancheTokenLike trancheToken = TrancheTokenLike(getTrancheToken(poolId, trancheId));
        require(address(trancheToken) != address(0), "PoolManager/unknown-token");

        require(
            keccak256(bytes(trancheToken.name())) != keccak256(bytes(name))
                || keccak256(bytes(trancheToken.symbol())) != keccak256(bytes(symbol)),
            "PoolManager/old-metadata"
        );

        trancheToken.file("name", name);
        trancheToken.file("symbol", symbol);
    }

    /// @inheritdoc IPoolManager
    function updateTrancheTokenPrice(
        uint64 poolId,
        bytes16 trancheId,
        uint128 assetId,
        uint128 price,
        uint64 computedAt
    ) public auth {
        Tranche storage tranche = pools[poolId].tranches[trancheId];
        require(tranche.token != address(0), "PoolManager/tranche-does-not-exist");

        address asset = idToAsset[assetId];
        require(computedAt >= tranche.prices[asset].computedAt, "PoolManager/cannot-set-older-price");

        tranche.prices[asset] = TrancheTokenPrice(price, computedAt);
        emit PriceUpdate(poolId, trancheId, asset, price, computedAt);
    }

    /// @inheritdoc IPoolManager
    function updateMember(uint64 poolId, bytes16 trancheId, address user, uint64 validUntil) public auth {
        require(user != address(escrow), "PoolManager/escrow-member-cannot-be-updated");

        TrancheTokenLike trancheToken = TrancheTokenLike(getTrancheToken(poolId, trancheId));
        require(address(trancheToken) != address(0), "PoolManager/unknown-token");

        RestrictionManagerLike restrictionManager = RestrictionManagerLike(address(trancheToken.restrictionManager()));
        restrictionManager.updateMember(user, validUntil);
    }

    /// @inheritdoc IPoolManager
    function freeze(uint64 poolId, bytes16 trancheId, address user) public auth {
        require(user != address(escrow), "PoolManager/escrow-cannot-be-frozen");

        TrancheTokenLike trancheToken = TrancheTokenLike(getTrancheToken(poolId, trancheId));
        require(address(trancheToken) != address(0), "PoolManager/unknown-token");

        RestrictionManagerLike restrictionManager = RestrictionManagerLike(address(trancheToken.restrictionManager()));
        restrictionManager.freeze(user);
    }

    /// @inheritdoc IPoolManager
    function unfreeze(uint64 poolId, bytes16 trancheId, address user) public auth {
        TrancheTokenLike trancheToken = TrancheTokenLike(getTrancheToken(poolId, trancheId));
        require(address(trancheToken) != address(0), "PoolManager/unknown-token");

        RestrictionManagerLike restrictionManager = RestrictionManagerLike(address(trancheToken.restrictionManager()));
        restrictionManager.unfreeze(user);
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
        escrow.approveMax(asset, address(investmentManager));

        emit AddAsset(assetId, asset);
    }

    /// @inheritdoc IPoolManager
    function handleTransfer(uint128 assetId, address recipient, uint128 amount) public auth {
        address asset = idToAsset[assetId];
        require(asset != address(0), "PoolManager/unknown-asset");

        escrow.approveMax(asset, address(this));
        SafeTransferLib.safeTransferFrom(asset, address(escrow), recipient, amount);
    }

    /// @inheritdoc IPoolManager
    function handleTransferTrancheTokens(uint64 poolId, bytes16 trancheId, address destinationAddress, uint128 amount)
        public
        auth
    {
        TrancheTokenLike trancheToken = TrancheTokenLike(getTrancheToken(poolId, trancheId));
        require(address(trancheToken) != address(0), "PoolManager/unknown-token");

        trancheToken.mint(destinationAddress, amount);
    }

    // --- Public functions ---
    // slither-disable-start reentrancy-eth
    /// @inheritdoc IPoolManager
    function deployTranche(uint64 poolId, bytes16 trancheId) public returns (address) {
        UndeployedTranche storage undeployedTranche = undeployedTranches[poolId][trancheId];
        require(undeployedTranche.decimals != 0, "PoolManager/tranche-not-added");

        address[] memory trancheTokenWards = new address[](2);
        trancheTokenWards[0] = address(investmentManager);
        trancheTokenWards[1] = address(this);

        address[] memory restrictionManagerWards = new address[](1);
        restrictionManagerWards[0] = address(this);

        address token = trancheTokenFactory.newTrancheToken(
            poolId,
            trancheId,
            undeployedTranche.tokenName,
            undeployedTranche.tokenSymbol,
            undeployedTranche.decimals,
            trancheTokenWards
        );
        address restrictionManager = restrictionManagerFactory.newRestrictionManager(
            undeployedTranche.restrictionSet, token, restrictionManagerWards
        );

        TrancheTokenLike(token).file("restrictionManager", restrictionManager);

        pools[poolId].tranches[trancheId].token = token;

        delete undeployedTranches[poolId][trancheId];

        // Give investment manager infinite approval for tranche tokens
        // in the escrow to transfer to the user on deposit or mint
        escrow.approveMax(token, address(investmentManager));

        emit DeployTranche(poolId, trancheId, token);
        return token;
    }
    // slither-disable-end reentrancy-eth

    /// @inheritdoc IPoolManager
    function deployVault(uint64 poolId, bytes16 trancheId, address asset) public returns (address) {
        Tranche storage tranche = pools[poolId].tranches[trancheId];
        require(tranche.token != address(0), "PoolManager/tranche-does-not-exist");
        require(isAllowedAsset(poolId, asset), "PoolManager/asset-not-supported");

        address vault = TrancheTokenLike(tranche.token).vault(asset);
        require(vault == address(0), "PoolManager/vault-already-deployed");

        // Rely investment manager on vault so it can mint tokens
        address[] memory vaultWards = new address[](1);
        vaultWards[0] = address(investmentManager);

        // Deploy vault
        vault = vaultFactory.newVault(
            poolId, trancheId, asset, tranche.token, address(escrow), address(investmentManager), vaultWards
        );
        vaultToAsset[vault] = asset;

        // Link vault to tranche token
        AuthLike(tranche.token).rely(vault);
        TrancheTokenLike(tranche.token).updateVault(asset, vault);

        // Give vault infinite approval for tranche tokens
        // in the escrow to burn on executed redemptions
        escrow.approveMax(tranche.token, vault);

        emit DeployVault(poolId, trancheId, asset, vault);
        return vault;
    }

    /// @inheritdoc IPoolManager
    function removeVault(uint64 poolId, bytes16 trancheId, address asset) public auth {
        require(pools[poolId].createdAt != 0, "PoolManager/pool-does-not-exist");
        Tranche storage tranche = pools[poolId].tranches[trancheId];
        require(tranche.token != address(0), "PoolManager/tranche-does-not-exist");

        address vault = TrancheTokenLike(tranche.token).vault(asset);
        require(vault != address(0), "PoolManager/vault-not-deployed");

        vaultFactory.denyVault(vault, address(investmentManager));

        AuthLike(tranche.token).deny(vault);
        TrancheTokenLike(tranche.token).updateVault(asset, address(0));

        escrow.unapprove(address(tranche.token), vault);

        emit RemoveVault(poolId, trancheId, asset, vault);
    }

    function updateCentrifugeGasPrice(uint256 price) public auth {
        require(price > 0, "PoolManager/price-cannot-be-zero");
        require(gasService.price() != price, "PoolManager/same-price-already-set");
        gasService.updateGasPrice(price);
    }

    // --- Helpers ---
    /// @inheritdoc IPoolManager
    function getTrancheToken(uint64 poolId, bytes16 trancheId) public view returns (address) {
        Tranche storage tranche = pools[poolId].tranches[trancheId];
        return tranche.token;
    }

    /// @inheritdoc IPoolManager
    function getVault(uint64 poolId, bytes16 trancheId, uint128 assetId) public view returns (address) {
        return TrancheTokenLike(pools[poolId].tranches[trancheId].token).vault(idToAsset[assetId]);
    }

    /// @inheritdoc IPoolManager
    function getVault(uint64 poolId, bytes16 trancheId, address asset) public view returns (address) {
        return TrancheTokenLike(pools[poolId].tranches[trancheId].token).vault(asset);
    }

    /// @inheritdoc IPoolManager
    function getTrancheTokenPrice(uint64 poolId, bytes16 trancheId, address asset)
        public
        view
        returns (uint128 price, uint64 computedAt)
    {
        TrancheTokenPrice memory value = pools[poolId].tranches[trancheId].prices[asset];
        price = value.price;
        computedAt = value.computedAt;
    }

    /// @inheritdoc IPoolManager
    function isAllowedAsset(uint64 poolId, address asset) public view returns (bool) {
        return pools[poolId].allowedCurrencies[asset];
    }
}
