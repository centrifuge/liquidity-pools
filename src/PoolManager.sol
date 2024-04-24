// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import {ERC7540VaultFactory} from "src/factories/ERC7540VaultFactory.sol";
import {RestrictionManagerFactoryLike} from "src/factories/RestrictionManagerFactory.sol";
import {TrancheTokenFactoryLike} from "src/factories/TrancheTokenFactory.sol";
import {TrancheTokenLike} from "./token/Tranche.sol";
import {RestrictionManagerLike} from "./token/RestrictionManager.sol";
import {IERC20Metadata} from "./interfaces/IERC20.sol";
import {Auth} from "./Auth.sol";
import {SafeTransferLib} from "./libraries/SafeTransferLib.sol";
import {MathLib} from "./libraries/MathLib.sol";
import {MessagesLib} from "src/libraries/MessagesLib.sol";
import {CastLib} from "src/libraries/CastLib.sol";
import {Pool, Tranche, TrancheTokenPrice, UndeployedTranche, IPoolManager} from "src/interfaces/IPoolManager.sol";
import {BytesLib} from "src/libraries/BytesLib.sol";

interface GatewayLike {
    function send(bytes memory message) external;
}

interface InvestmentManagerLike {
    function vaults(uint64 poolId, bytes16 trancheId, address currency) external returns (address);
    function getTrancheToken(uint64 _poolId, bytes16 _trancheId) external view returns (address);
}

interface EscrowLike {
    function approve(address token, address spender, uint256 value) external;
}

interface AuthLike {
    function rely(address user) external;
    function deny(address user) external;
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

    EscrowLike public immutable escrow;

    GatewayLike public gateway;
    InvestmentManagerLike public investmentManager;
    TrancheTokenFactoryLike public trancheTokenFactory;
    ERC7540VaultFactory public vaultFactory;
    RestrictionManagerFactoryLike public restrictionManagerFactory;

    mapping(uint64 poolId => Pool) public pools;
    mapping(uint128 currencyId => address) public currencyIdToAddress;
    mapping(address => uint128 currencyId) public assetToId;
    mapping(uint64 poolId => mapping(bytes16 => UndeployedTranche)) public undeployedTranches;

    constructor(
        address escrow_,
        address vaultFactory_,
        address restrictionManagerFactory_,
        address trancheTokenFactory_
    ) {
        escrow = EscrowLike(escrow_);
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
        else revert("PoolManager/file-unrecognized-param");
        emit File(what, data);
    }

    function recoverTokens(address token, address to, uint256 amount) external auth {
        SafeTransferLib.safeTransfer(token, to, amount);
    }

    // --- Outgoing message handling ---
    /// @inheritdoc IPoolManager
    function transfer(address currency, bytes32 recipient, uint128 amount) external {
        uint128 currencyId = assetToId[currency];
        require(currencyId != 0, "PoolManager/unknown-currency");

        SafeTransferLib.safeTransferFrom(currency, msg.sender, address(escrow), amount);

        gateway.send(abi.encodePacked(uint8(MessagesLib.Call.Transfer), currencyId, msg.sender, recipient, amount));
        emit TransferCurrency(currency, recipient, amount);
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
            )
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
            )
        );

        emit TransferTrancheTokensToEVM(poolId, trancheId, destinationChainId, destinationAddress, amount);
    }

    // --- Incoming message handling ---
    /// @inheritdoc IPoolManager
    function handle(bytes calldata message) external auth {
        MessagesLib.Call call = MessagesLib.messageType(message);

        if (call == MessagesLib.Call.AddCurrency) {
            addCurrency(message.toUint128(1), message.toAddress(17));
        } else if (call == MessagesLib.Call.AddPool) {
            addPool(message.toUint64(1));
        } else if (call == MessagesLib.Call.AllowInvestmentCurrency) {
            allowInvestmentCurrency(message.toUint64(1), message.toUint128(9));
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
        } else if (call == MessagesLib.Call.DisallowInvestmentCurrency) {
            disallowInvestmentCurrency(message.toUint64(1), message.toUint128(9));
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
    function allowInvestmentCurrency(uint64 poolId, uint128 currencyId) public auth {
        Pool storage pool = pools[poolId];
        require(pool.createdAt != 0, "PoolManager/invalid-pool");

        address currency = currencyIdToAddress[currencyId];
        require(currency != address(0), "PoolManager/unknown-currency");

        pools[poolId].allowedCurrencies[currency] = true;
        emit AllowInvestmentCurrency(poolId, currency);
    }

    /// @inheritdoc IPoolManager
    function disallowInvestmentCurrency(uint64 poolId, uint128 currencyId) public auth {
        Pool storage pool = pools[poolId];
        require(pool.createdAt != 0, "PoolManager/invalid-pool");

        address currency = currencyIdToAddress[currencyId];
        require(currency != address(0), "PoolManager/unknown-currency");

        pools[poolId].allowedCurrencies[currency] = false;
        emit DisallowInvestmentCurrency(poolId, currency);
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
        uint128 currencyId,
        uint128 price,
        uint64 computedAt
    ) public auth {
        Tranche storage tranche = pools[poolId].tranches[trancheId];
        require(tranche.token != address(0), "PoolManager/tranche-does-not-exist");

        address currency = currencyIdToAddress[currencyId];
        require(computedAt >= tranche.prices[currency].computedAt, "PoolManager/cannot-set-older-price");

        tranche.prices[currency] = TrancheTokenPrice(price, computedAt);
        emit PriceUpdate(poolId, trancheId, currency, price, computedAt);
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
    function addCurrency(uint128 currencyId, address currency) public auth {
        // Currency index on the Centrifuge side should start at 1
        require(currencyId != 0, "PoolManager/currency-id-has-to-be-greater-than-0");
        require(currencyIdToAddress[currencyId] == address(0), "PoolManager/currency-id-in-use");
        require(assetToId[currency] == 0, "PoolManager/currency-address-in-use");

        uint8 currencyDecimals = IERC20Metadata(currency).decimals();
        require(currencyDecimals >= MIN_DECIMALS, "PoolManager/too-few-currency-decimals");
        require(currencyDecimals <= MAX_DECIMALS, "PoolManager/too-many-currency-decimals");

        currencyIdToAddress[currencyId] = currency;
        assetToId[currency] = currencyId;

        // Give investment manager infinite approval for currency
        // in the escrow to transfer to the user on redeem or withdraw
        escrow.approve(currency, address(investmentManager), type(uint256).max);

        emit AddCurrency(currencyId, currency);
    }

    /// @inheritdoc IPoolManager
    function handleTransfer(uint128 currencyId, address recipient, uint128 amount) public auth {
        address currency = currencyIdToAddress[currencyId];
        require(currency != address(0), "PoolManager/unknown-currency");

        escrow.approve(currency, address(this), amount);
        SafeTransferLib.safeTransferFrom(currency, address(escrow), recipient, amount);
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
        escrow.approve(token, address(investmentManager), type(uint256).max);

        emit DeployTranche(poolId, trancheId, token);
        return token;
    }
    // slither-disable-end reentrancy-eth

    /// @inheritdoc IPoolManager
    function deployVault(uint64 poolId, bytes16 trancheId, address currency) public returns (address) {
        Tranche storage tranche = pools[poolId].tranches[trancheId];
        require(tranche.token != address(0), "PoolManager/tranche-does-not-exist");
        require(isAllowedAsset(poolId, currency), "PoolManager/currency-not-supported");

        address vault = TrancheTokenLike(tranche.token).vault(currency);
        require(vault == address(0), "PoolManager/vault-already-deployed");

        // Rely investment manager on vault so it can mint tokens
        address[] memory vaultWards = new address[](1);
        vaultWards[0] = address(investmentManager);

        // Deploy vault
        vault = vaultFactory.newVault(
            poolId, trancheId, currency, tranche.token, address(escrow), address(investmentManager), vaultWards
        );

        // Link vault to tranche token
        AuthLike(tranche.token).rely(vault);
        TrancheTokenLike(tranche.token).file("trustedForwarder", vault, true);
        TrancheTokenLike(tranche.token).file("vault", currency, vault);

        // Give vault infinite approval for tranche tokens
        // in the escrow to burn on executed redemptions
        escrow.approve(tranche.token, vault, type(uint256).max);

        emit DeployVault(poolId, trancheId, currency, vault);
        return vault;
    }

    /// @inheritdoc IPoolManager
    function removeVault(uint64 poolId, bytes16 trancheId, address currency) public auth {
        require(pools[poolId].createdAt != 0, "PoolManager/pool-does-not-exist");
        Tranche storage tranche = pools[poolId].tranches[trancheId];
        require(tranche.token != address(0), "PoolManager/tranche-does-not-exist");

        address vault = TrancheTokenLike(tranche.token).vault(currency);
        require(vault != address(0), "PoolManager/vault-not-deployed");

        vaultFactory.denyVault(vault, address(investmentManager));

        AuthLike(tranche.token).deny(vault);
        TrancheTokenLike(tranche.token).file("trustedForwarder", vault, false);
        TrancheTokenLike(tranche.token).file("vault", currency, address(0));

        escrow.approve(address(tranche.token), vault, 0);

        emit RemoveVault(poolId, trancheId, currency, vault);
    }

    // --- Helpers ---
    /// @inheritdoc IPoolManager
    function getTrancheToken(uint64 poolId, bytes16 trancheId) public view returns (address) {
        Tranche storage tranche = pools[poolId].tranches[trancheId];
        return tranche.token;
    }

    /// @inheritdoc IPoolManager
    function getVault(uint64 poolId, bytes16 trancheId, uint128 currencyId) public view returns (address) {
        return TrancheTokenLike(pools[poolId].tranches[trancheId].token).vault(currencyIdToAddress[currencyId]);
    }

    /// @inheritdoc IPoolManager
    function getVault(uint64 poolId, bytes16 trancheId, address currency) public view returns (address) {
        return TrancheTokenLike(pools[poolId].tranches[trancheId].token).vault(currency);
    }

    /// @inheritdoc IPoolManager
    function getTrancheTokenPrice(uint64 poolId, bytes16 trancheId, address currency)
        public
        view
        returns (uint128 price, uint64 computedAt)
    {
        TrancheTokenPrice memory value = pools[poolId].tranches[trancheId].prices[currency];
        price = value.price;
        computedAt = value.computedAt;
    }

    /// @inheritdoc IPoolManager
    function isAllowedAsset(uint64 poolId, address currency) public view returns (bool) {
        return pools[poolId].allowedCurrencies[currency];
    }
}
