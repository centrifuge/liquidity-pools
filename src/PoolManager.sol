// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import {LiquidityPoolFactoryLike} from "src/factories/LiquidityPoolFactory.sol";
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

interface GatewayLike {
    function send(bytes memory message) external;
}

interface InvestmentManagerLike {
    function liquidityPools(uint64 poolId, bytes16 trancheId, address currency) external returns (address);
    function getTrancheToken(uint64 _poolId, bytes16 _trancheId) external view returns (address);
    function userEscrow() external view returns (address);
}

interface EscrowLike {
    function approve(address token, address spender, uint256 value) external;
}

interface AuthLike {
    function rely(address user) external;
    function deny(address user) external;
}

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

/// @title  Pool Manager
/// @notice This contract manages which pools & tranches exist,
///         as well as managing allowed pool currencies, and incoming and outgoing transfers.
contract PoolManager is Auth {
    using MathLib for uint256;
    using CastLib for *;

    uint8 internal constant MIN_DECIMALS = 1;
    uint8 internal constant MAX_DECIMALS = 18;

    EscrowLike public immutable escrow;

    GatewayLike public gateway;
    InvestmentManagerLike public investmentManager;
    TrancheTokenFactoryLike public trancheTokenFactory;
    LiquidityPoolFactoryLike public liquidityPoolFactory;
    RestrictionManagerFactoryLike public restrictionManagerFactory;

    mapping(uint64 poolId => Pool) public pools;
    mapping(uint64 poolId => mapping(bytes16 => UndeployedTranche)) public undeployedTranches;

    /// @dev Chain agnostic currency id -> evm currency address and reverse mapping
    mapping(uint128 currencyId => address) public currencyIdToAddress;
    mapping(address => uint128 currencyId) public currencyAddressToId;

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

    constructor(
        address escrow_,
        address liquidityPoolFactory_,
        address restrictionManagerFactory_,
        address trancheTokenFactory_
    ) {
        escrow = EscrowLike(escrow_);
        liquidityPoolFactory = LiquidityPoolFactoryLike(liquidityPoolFactory_);
        restrictionManagerFactory = RestrictionManagerFactoryLike(restrictionManagerFactory_);
        trancheTokenFactory = TrancheTokenFactoryLike(trancheTokenFactory_);

        wards[msg.sender] = 1;
        emit Rely(msg.sender);
    }

    /// @dev Gateway must be msg.sender for incoming message handling.
    modifier onlyGateway() {
        require(msg.sender == address(gateway), "PoolManager/not-the-gateway");
        _;
    }

    // --- Administration ---
    function file(bytes32 what, address data) external auth {
        if (what == "gateway") gateway = GatewayLike(data);
        else if (what == "investmentManager") investmentManager = InvestmentManagerLike(data);
        else if (what == "trancheTokenFactory") trancheTokenFactory = TrancheTokenFactoryLike(data);
        else if (what == "liquidityPoolFactory") liquidityPoolFactory = LiquidityPoolFactoryLike(data);
        else if (what == "restrictionManagerFactory") restrictionManagerFactory = RestrictionManagerFactoryLike(data);
        else revert("PoolManager/file-unrecognized-param");
        emit File(what, data);
    }

    // --- Outgoing message handling ---
    function transfer(address currency, bytes32 recipient, uint128 amount) external {
        uint128 currencyId = currencyAddressToId[currency];
        require(currencyId != 0, "PoolManager/unknown-currency");

        SafeTransferLib.safeTransferFrom(currency, msg.sender, address(escrow), amount);

        gateway.send(abi.encodePacked(uint8(MessagesLib.Call.Transfer), currencyId, msg.sender, recipient, amount));
        emit TransferCurrency(currency, recipient, amount);
    }

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
    /// @notice    New pool details from an existing Centrifuge pool are added.
    /// @dev       The function can only be executed by the gateway contract.
    function addPool(uint64 poolId) public onlyGateway {
        Pool storage pool = pools[poolId];
        require(pool.createdAt == 0, "PoolManager/pool-already-added");
        pool.createdAt = block.timestamp;
        emit AddPool(poolId);
    }

    /// @notice     Centrifuge pools can support multiple currencies for investing. this function adds
    ///             a new supported currency to the pool details.
    ///             Adding new currencies allow the creation of new liquidity pools for the underlying Centrifuge pool.
    /// @dev        The function can only be executed by the gateway contract.
    function allowInvestmentCurrency(uint64 poolId, uint128 currencyId) public onlyGateway {
        Pool storage pool = pools[poolId];
        require(pool.createdAt != 0, "PoolManager/invalid-pool");

        address currency = currencyIdToAddress[currencyId];
        require(currency != address(0), "PoolManager/unknown-currency");

        pools[poolId].allowedCurrencies[currency] = true;
        emit AllowInvestmentCurrency(poolId, currency);
    }

    function disallowInvestmentCurrency(uint64 poolId, uint128 currencyId) public onlyGateway {
        Pool storage pool = pools[poolId];
        require(pool.createdAt != 0, "PoolManager/invalid-pool");

        address currency = currencyIdToAddress[currencyId];
        require(currency != address(0), "PoolManager/unknown-currency");

        pools[poolId].allowedCurrencies[currency] = false;
        emit DisallowInvestmentCurrency(poolId, currency);
    }

    /// @notice     New tranche details from an existing Centrifuge pool are added.
    /// @dev        The function can only be executed by the gateway contract.
    function addTranche(
        uint64 poolId,
        bytes16 trancheId,
        string memory tokenName,
        string memory tokenSymbol,
        uint8 decimals,
        uint8 restrictionSet
    ) public onlyGateway {
        require(decimals >= MIN_DECIMALS, "PoolManager/too-few-tranche-token-decimals");
        require(decimals <= MAX_DECIMALS, "PoolManager/too-many-tranche-token-decimals");

        Pool storage pool = pools[poolId];
        require(pool.createdAt != 0, "PoolManager/invalid-pool");

        UndeployedTranche storage undeployedTranche = undeployedTranches[poolId][trancheId];
        require(undeployedTranche.decimals == 0, "PoolManager/tranche-already-exists");
        require(getTrancheToken(poolId, trancheId) == address(0), "PoolManager/tranche-already-deployed");

        undeployedTranche.decimals = decimals;
        undeployedTranche.tokenName = tokenName;
        undeployedTranche.tokenSymbol = tokenSymbol;
        undeployedTranche.restrictionSet = restrictionSet;

        emit AddTranche(poolId, trancheId);
    }

    function updateTrancheTokenMetadata(
        uint64 poolId,
        bytes16 trancheId,
        string memory tokenName,
        string memory tokenSymbol
    ) public onlyGateway {
        TrancheTokenLike trancheToken = TrancheTokenLike(getTrancheToken(poolId, trancheId));
        require(address(trancheToken) != address(0), "PoolManager/unknown-token");

        require(
            keccak256(bytes(trancheToken.name())) != keccak256(bytes(tokenName))
                || keccak256(bytes(trancheToken.symbol())) != keccak256(bytes(tokenSymbol)),
            "PoolManager/old-metadata"
        );

        trancheToken.file("name", tokenName);
        trancheToken.file("symbol", tokenSymbol);
    }

    function updateTrancheTokenPrice(
        uint64 poolId,
        bytes16 trancheId,
        uint128 currencyId,
        uint128 price,
        uint64 computedAt
    ) public onlyGateway {
        Tranche storage tranche = pools[poolId].tranches[trancheId];
        require(tranche.token != address(0), "PoolManager/tranche-does-not-exist");

        address currency = currencyIdToAddress[currencyId];
        require(computedAt >= tranche.prices[currency].computedAt, "PoolManager/cannot-set-older-price");

        tranche.prices[currency] = TrancheTokenPrice(price, computedAt);
        emit PriceUpdate(poolId, trancheId, currency, price, computedAt);
    }

    function updateMember(uint64 poolId, bytes16 trancheId, address user, uint64 validUntil) public onlyGateway {
        require(user != address(escrow), "PoolManager/escrow-member-cannot-be-updated");

        TrancheTokenLike trancheToken = TrancheTokenLike(getTrancheToken(poolId, trancheId));
        require(address(trancheToken) != address(0), "PoolManager/unknown-token");

        RestrictionManagerLike restrictionManager = RestrictionManagerLike(address(trancheToken.restrictionManager()));
        restrictionManager.updateMember(user, validUntil);
    }

    function freeze(uint64 poolId, bytes16 trancheId, address user) public onlyGateway {
        require(user != address(escrow), "PoolManager/escrow-cannot-be-frozen");

        TrancheTokenLike trancheToken = TrancheTokenLike(getTrancheToken(poolId, trancheId));
        require(address(trancheToken) != address(0), "PoolManager/unknown-token");

        RestrictionManagerLike restrictionManager = RestrictionManagerLike(address(trancheToken.restrictionManager()));
        restrictionManager.freeze(user);
    }

    function unfreeze(uint64 poolId, bytes16 trancheId, address user) public onlyGateway {
        TrancheTokenLike trancheToken = TrancheTokenLike(getTrancheToken(poolId, trancheId));
        require(address(trancheToken) != address(0), "PoolManager/unknown-token");

        RestrictionManagerLike restrictionManager = RestrictionManagerLike(address(trancheToken.restrictionManager()));
        restrictionManager.unfreeze(user);
    }

    /// @notice A global chain agnostic currency index is maintained on Centrifuge. This function maps
    ///         a currency from the Centrifuge index to its corresponding address on the evm chain.
    ///         The chain agnostic currency id has to be used to pass currency information to the Centrifuge.
    /// @dev    This function can only be executed by the gateway contract.
    function addCurrency(uint128 currencyId, address currency) public onlyGateway {
        // Currency index on the Centrifuge side should start at 1
        require(currencyId != 0, "PoolManager/currency-id-has-to-be-greater-than-0");
        require(currencyIdToAddress[currencyId] == address(0), "PoolManager/currency-id-in-use");
        require(currencyAddressToId[currency] == 0, "PoolManager/currency-address-in-use");

        uint8 currencyDecimals = IERC20Metadata(currency).decimals();
        require(currencyDecimals >= MIN_DECIMALS, "PoolManager/too-few-currency-decimals");
        require(currencyDecimals <= MAX_DECIMALS, "PoolManager/too-many-currency-decimals");

        currencyIdToAddress[currencyId] = currency;
        currencyAddressToId[currency] = currencyId;

        // Give investment manager infinite approval for currency in the escrow
        // to transfer to the user escrow on redeem, withdraw or transfer
        escrow.approve(currency, investmentManager.userEscrow(), type(uint256).max);

        emit AddCurrency(currencyId, currency);
    }

    function handleTransfer(uint128 currencyId, address recipient, uint128 amount) public onlyGateway {
        address currency = currencyIdToAddress[currencyId];
        require(currency != address(0), "PoolManager/unknown-currency");

        escrow.approve(currency, address(this), amount);
        SafeTransferLib.safeTransferFrom(currency, address(escrow), recipient, amount);
    }

    function handleTransferTrancheTokens(uint64 poolId, bytes16 trancheId, address destinationAddress, uint128 amount)
        public
        onlyGateway
    {
        TrancheTokenLike trancheToken = TrancheTokenLike(getTrancheToken(poolId, trancheId));
        require(address(trancheToken) != address(0), "PoolManager/unknown-token");

        trancheToken.mint(destinationAddress, amount);
    }

    // --- Public functions ---
    // slither-disable-start reentrancy-eth
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

    function deployLiquidityPool(uint64 poolId, bytes16 trancheId, address currency) public returns (address) {
        Tranche storage tranche = pools[poolId].tranches[trancheId];
        require(tranche.token != address(0), "PoolManager/tranche-does-not-exist");
        require(isAllowedAsInvestmentCurrency(poolId, currency), "PoolManager/currency-not-supported");

        address liquidityPool = tranche.liquidityPools[currency];
        require(liquidityPool == address(0), "PoolManager/liquidity-pool-already-deployed");

        // Rely investment manager on liquidity pool so it can mint tokens
        address[] memory liquidityPoolWards = new address[](1);
        liquidityPoolWards[0] = address(investmentManager);

        // Deploy liquidity pool
        liquidityPool = liquidityPoolFactory.newLiquidityPool(
            poolId, trancheId, currency, tranche.token, address(escrow), address(investmentManager), liquidityPoolWards
        );
        tranche.liquidityPools[currency] = liquidityPool;

        // Rely liquidity pool on investment manager so it can send outgoing calls
        AuthLike(address(investmentManager)).rely(liquidityPool);

        // Link liquidity pool to tranche token
        AuthLike(tranche.token).rely(liquidityPool);
        TrancheTokenLike(tranche.token).addTrustedForwarder(liquidityPool);

        // Give liquidity pool infinite approval for tranche tokens
        // in the escrow to burn on executed redemptions
        escrow.approve(tranche.token, liquidityPool, type(uint256).max);

        emit DeployLiquidityPool(poolId, trancheId, currency, liquidityPool);
        return liquidityPool;
    }

    function removeLiquidityPool(uint64 poolId, bytes16 trancheId, address currency) public auth {
        require(pools[poolId].createdAt != 0, "PoolManager/pool-does-not-exist");
        Tranche storage tranche = pools[poolId].tranches[trancheId];
        require(tranche.token != address(0), "PoolManager/tranche-does-not-exist");

        address liquidityPool = tranche.liquidityPools[currency];
        require(liquidityPool != address(0), "PoolManager/liquidity-pool-not-deployed");

        delete tranche.liquidityPools[currency];

        AuthLike(address(investmentManager)).deny(liquidityPool);

        AuthLike(tranche.token).deny(liquidityPool);
        TrancheTokenLike(tranche.token).removeTrustedForwarder(liquidityPool);

        escrow.approve(address(tranche.token), liquidityPool, 0);

        emit RemoveLiquidityPool(poolId, trancheId, currency, liquidityPool);
    }

    // --- Helpers ---
    function getTrancheToken(uint64 poolId, bytes16 trancheId) public view returns (address) {
        Tranche storage tranche = pools[poolId].tranches[trancheId];
        return tranche.token;
    }

    function getLiquidityPool(uint64 poolId, bytes16 trancheId, uint128 currencyId) public view returns (address) {
        return pools[poolId].tranches[trancheId].liquidityPools[currencyIdToAddress[currencyId]];
    }

    function getLiquidityPool(uint64 poolId, bytes16 trancheId, address currency) public view returns (address) {
        return pools[poolId].tranches[trancheId].liquidityPools[currency];
    }

    function getTrancheTokenPrice(uint64 poolId, bytes16 trancheId, address currency)
        public
        view
        returns (uint256 price, uint64 computedAt)
    {
        TrancheTokenPrice memory value = pools[poolId].tranches[trancheId].prices[currency];
        price = value.price;
        computedAt = value.computedAt;
    }

    function isAllowedAsInvestmentCurrency(uint64 poolId, address currency) public view returns (bool) {
        return pools[poolId].allowedCurrencies[currency];
    }
}
