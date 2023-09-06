// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import {TrancheTokenFactoryLike, LiquidityPoolFactoryLike} from "./util/Factory.sol";
import {TrancheTokenLike} from "./token/Tranche.sol";
import {MemberlistLike} from "./token/RestrictionManager.sol";
import {IERC20} from "./interfaces/IERC20.sol";
import {Auth} from "./util/Auth.sol";
import {SafeTransferLib} from "./util/SafeTransferLib.sol";

interface GatewayLike {
    function transferTrancheTokensToCentrifuge(
        uint64 poolId,
        bytes16 trancheId,
        address sender,
        bytes32 destinationAddress,
        uint128 amount
    ) external;
    function transferTrancheTokensToEVM(
        uint64 poolId,
        bytes16 trancheId,
        address sender,
        uint64 destinationChainId,
        address destinationAddress,
        uint128 amount
    ) external;
    function transfer(uint128 currency, address sender, bytes32 recipient, uint128 amount) external;
}

interface LiquidityPoolLike {
    function hasMember(address) external returns (bool);
}

interface InvestmentManagerLike {
    function liquidityPools(uint64 poolId, bytes16 trancheId, address currency) external returns (address);
    function getTrancheToken(uint64 _poolId, bytes16 _trancheId) external view returns (address);
    function userEscrow() external view returns (address);
}

interface EscrowLike {
    function approve(address token, address spender, uint256 value) external;
}

interface ERC2771Like {
    function addLiquidityPool(address forwarder) external;
}

interface AuthLike {
    function rely(address usr) external;
}

/// @dev Centrifuge pools
struct Pool {
    uint64 poolId;
    uint256 createdAt;
    mapping(bytes16 => Tranche) tranches;
    mapping(address => bool) allowedCurrencies;
}

/// @dev Each Centrifuge pool is associated to 1 or more tranches
struct Tranche {
    address token;
    uint64 poolId;
    bytes16 trancheId;
    // important: the decimals of the leading pool currency. Liquidity Pool shares have to be denomatimated with the same precision.
    uint8 decimals;
    uint256 createdAt;
    string tokenName;
    string tokenSymbol;
    /// @dev Each tranche can have multiple liquidity pools deployed,
    /// each linked to a unique investment currency (asset)
    mapping(address => address) liquidityPools; // currency -> liquidity pool address
}

/// @title  Pool Manager
/// @notice This contract manages which pools & tranches exist,
///         as well as managing allowed pool currencies, and incoming and outgoing transfers.
contract PoolManager is Auth {
    uint8 internal constant MAX_CURRENCY_DECIMALS = 18;

    EscrowLike public immutable escrow;
    LiquidityPoolFactoryLike public immutable liquidityPoolFactory;
    TrancheTokenFactoryLike public immutable trancheTokenFactory;

    GatewayLike public gateway;
    InvestmentManagerLike public investmentManager;

    mapping(uint64 => Pool) public pools;

    /// @dev Chain agnostic currency id -> evm currency address and reverse mapping
    mapping(uint128 => address) public currencyIdToAddress;
    mapping(address => uint128) public currencyAddressToId;

    // --- Events ---
    event File(bytes32 indexed what, address data);
    event PoolAdded(uint64 indexed poolId);
    event PoolCurrencyAllowed(uint128 indexed currency, uint64 indexed poolId);
    event TrancheAdded(uint64 indexed poolId, bytes16 indexed trancheId);
    event TrancheDeployed(uint64 indexed poolId, bytes16 indexed trancheId, address indexed token);
    event CurrencyAdded(uint128 indexed currency, address indexed currencyAddress);
    event LiquidityPoolDeployed(uint64 indexed poolId, bytes16 indexed trancheId, address indexed liquidityPoool);
    event TrancheTokenDeployed(uint64 indexed poolId, bytes16 indexed trancheId);

    constructor(address escrow_, address liquidityPoolFactory_, address trancheTokenFactory_) {
        escrow = EscrowLike(escrow_);
        liquidityPoolFactory = LiquidityPoolFactoryLike(liquidityPoolFactory_);
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
        else revert("PoolManager/file-unrecognized-param");
        emit File(what, data);
    }

    // --- Outgoing message handling ---
    function transfer(address currencyAddress, bytes32 recipient, uint128 amount) public {
        uint128 currency = currencyAddressToId[currencyAddress];
        require(currency != 0, "PoolManager/unknown-currency");

        SafeTransferLib.safeTransferFrom(currencyAddress, msg.sender, address(escrow), amount);
        gateway.transfer(currency, msg.sender, recipient, amount);
    }

    function transferTrancheTokensToCentrifuge(
        uint64 poolId,
        bytes16 trancheId,
        bytes32 destinationAddress,
        uint128 amount
    ) public {
        TrancheTokenLike trancheToken = TrancheTokenLike(getTrancheToken(poolId, trancheId));
        require(address(trancheToken) != address(0), "PoolManager/unknown-token");

        trancheToken.burn(msg.sender, amount);
        gateway.transferTrancheTokensToCentrifuge(poolId, trancheId, msg.sender, destinationAddress, amount);
    }

    function transferTrancheTokensToEVM(
        uint64 poolId,
        bytes16 trancheId,
        uint64 destinationChainId,
        address destinationAddress,
        uint128 amount
    ) public {
        TrancheTokenLike trancheToken = TrancheTokenLike(getTrancheToken(poolId, trancheId));
        require(address(trancheToken) != address(0), "PoolManager/unknown-token");

        trancheToken.burn(msg.sender, amount);
        gateway.transferTrancheTokensToEVM(
            poolId, trancheId, msg.sender, destinationChainId, destinationAddress, amount
        );
    }

    // --- Incoming message handling ---
    /// @notice    New pool details from an existing Centrifuge pool are added.
    /// @dev       The function can only be executed by the gateway contract.
    function addPool(uint64 poolId) public onlyGateway {
        Pool storage pool = pools[poolId];
        require(pool.createdAt == 0, "PoolManager/pool-already-added");
        pool.poolId = poolId;
        pool.createdAt = block.timestamp;
        emit PoolAdded(poolId);
    }

    /// @notice     Centrifuge pools can support multiple currencies for investing. this function adds a new supported currency to the pool details.
    ///             Adding new currencies allow the creation of new liquidity pools for the underlying Centrifuge pool.
    /// @dev        The function can only be executed by the gateway contract.
    function allowPoolCurrency(uint64 poolId, uint128 currency) public onlyGateway {
        Pool storage pool = pools[poolId];
        require(pool.createdAt != 0, "PoolManager/invalid-pool");

        address currencyAddress = currencyIdToAddress[currency];
        require(currencyAddress != address(0), "PoolManager/unknown-currency");

        pools[poolId].allowedCurrencies[currencyAddress] = true;
        emit PoolCurrencyAllowed(currency, poolId);
    }

    /// @notice     New tranche details from an existng Centrifuge pool are added.
    /// @dev        The function can only be executed by the gateway contract.
    function addTranche(
        uint64 poolId,
        bytes16 trancheId,
        string memory tokenName,
        string memory tokenSymbol,
        uint8 decimals
    ) public onlyGateway {
        Pool storage pool = pools[poolId];
        require(pool.createdAt != 0, "PoolManager/invalid-pool");
        Tranche storage tranche = pool.tranches[trancheId];
        require(tranche.createdAt == 0, "PoolManager/tranche-already-exists");

        tranche.poolId = poolId;
        tranche.trancheId = trancheId;
        tranche.decimals = decimals;
        tranche.tokenName = tokenName;
        tranche.tokenSymbol = tokenSymbol;
        tranche.createdAt = block.timestamp;

        emit TrancheAdded(poolId, trancheId);
    }

    function updateTrancheTokenMetadata(
        uint64 poolId,
        bytes16 trancheId,
        string memory tokenName,
        string memory tokenSymbol
    ) public onlyGateway {
        TrancheTokenLike trancheToken = TrancheTokenLike(getTrancheToken(poolId, trancheId));
        require(address(trancheToken) != address(0), "PoolManager/unknown-token");

        trancheToken.file("name", tokenName);
        trancheToken.file("symbol", tokenSymbol);
    }

    function updateMember(uint64 poolId, bytes16 trancheId, address user, uint64 validUntil) public onlyGateway {
        TrancheTokenLike trancheToken = TrancheTokenLike(getTrancheToken(poolId, trancheId));
        require(address(trancheToken) != address(0), "PoolManager/unknown-token");

        MemberlistLike memberlist = MemberlistLike(address(trancheToken.restrictionManager()));
        memberlist.updateMember(user, validUntil);
    }

    /// @notice A global chain agnostic currency index is maintained on Centrifuge. This function maps a currency from the Centrifuge index to its corresponding address on the evm chain.
    ///         The chain agnostic currency id has to be used to pass currency information to the Centrifuge.
    /// @dev    This function can only be executed by the gateway contract.
    function addCurrency(uint128 currency, address currencyAddress) public onlyGateway {
        // Currency index on the Centrifuge side should start at 1
        require(currency != 0, "PoolManager/currency-id-has-to-be-greater-than-0");
        require(currencyIdToAddress[currency] == address(0), "PoolManager/currency-id-in-use");
        require(currencyAddressToId[currencyAddress] == 0, "PoolManager/currency-address-in-use");
        require(IERC20(currencyAddress).decimals() <= MAX_CURRENCY_DECIMALS, "PoolManager/too-many-currency-decimals");

        currencyIdToAddress[currency] = currencyAddress;
        currencyAddressToId[currencyAddress] = currency;

        // Enable taking the currency out of escrow in case of redemptions
        EscrowLike(escrow).approve(currencyAddress, investmentManager.userEscrow(), type(uint256).max);

        // Enable taking the currency out of escrow in case of decrease invest orders
        EscrowLike(escrow).approve(currencyAddress, address(investmentManager), type(uint256).max);

        emit CurrencyAdded(currency, currencyAddress);
    }

    function handleTransfer(uint128 currency, address recipient, uint128 amount) public onlyGateway {
        address currencyAddress = currencyIdToAddress[currency];
        require(currencyAddress != address(0), "PoolManager/unknown-currency");

        EscrowLike(escrow).approve(currencyAddress, address(this), amount);
        SafeTransferLib.safeTransferFrom(currencyAddress, address(escrow), recipient, amount);
    }

    function handleTransferTrancheTokens(uint64 poolId, bytes16 trancheId, address destinationAddress, uint128 amount)
        public
        onlyGateway
    {
        TrancheTokenLike trancheToken = TrancheTokenLike(getTrancheToken(poolId, trancheId));
        require(address(trancheToken) != address(0), "PoolManager/unknown-token");

        require(
            MemberlistLike(address(trancheToken.restrictionManager())).hasMember(destinationAddress),
            "PoolManager/not-a-member"
        );
        trancheToken.mint(destinationAddress, amount);
    }

    // --- Public functions ---
    function deployTranche(uint64 poolId, bytes16 trancheId) public returns (address) {
        Tranche storage tranche = pools[poolId].tranches[trancheId];
        require(tranche.token == address(0), "PoolManager/tranche-already-deployed");
        require(tranche.createdAt != 0, "PoolManager/tranche-not-added");

        address[] memory trancheTokenWards = new address[](2);
        trancheTokenWards[0] = address(investmentManager);
        trancheTokenWards[1] = address(this);

        address[] memory memberlistWards = new address[](1);
        memberlistWards[0] = address(this);

        address token = trancheTokenFactory.newTrancheToken(
            poolId,
            trancheId,
            tranche.tokenName,
            tranche.tokenSymbol,
            tranche.decimals,
            trancheTokenWards,
            memberlistWards
        );

        tranche.token = token;
        emit TrancheTokenDeployed(poolId, trancheId);
        return token;
    }

    function deployLiquidityPool(uint64 poolId, bytes16 trancheId, address currency) public returns (address) {
        Tranche storage tranche = pools[poolId].tranches[trancheId];
        require(tranche.token != address(0), "PoolManager/tranche-does-not-exist"); // Tranche must have been added
        require(isAllowedAsPoolCurrency(poolId, currency), "PoolManager/currency-not-supported"); // Currency must be supported by pool

        address liquidityPool = tranche.liquidityPools[currency];
        require(liquidityPool == address(0), "PoolManager/liquidityPool-already-deployed");
        require(pools[poolId].createdAt != 0, "PoolManager/pool-does-not-exist");

        address[] memory liquidityPoolWards = new address[](1);
        liquidityPoolWards[0] = address(investmentManager);
        liquidityPool = liquidityPoolFactory.newLiquidityPool(
            poolId, trancheId, currency, tranche.token, address(investmentManager), liquidityPoolWards
        );

        tranche.liquidityPools[currency] = liquidityPool;
        AuthLike(address(investmentManager)).rely(liquidityPool);

        // Enable LP to take the tranche tokens out of escrow in case if investments
        AuthLike(tranche.token).rely(liquidityPool); // Add liquidityPool as ward on tranche token
        ERC2771Like(tranche.token).addLiquidityPool(liquidityPool);
        EscrowLike(escrow).approve(liquidityPool, address(investmentManager), type(uint256).max); // Approve investment manager on tranche token for coordinating transfers
        EscrowLike(escrow).approve(liquidityPool, liquidityPool, type(uint256).max); // Approve liquidityPool on tranche token to be able to burn

        emit LiquidityPoolDeployed(poolId, trancheId, liquidityPool);
        return liquidityPool;
    }

    // --- Helpers ---
    function getTrancheToken(uint64 poolId, bytes16 trancheId) public view returns (address) {
        Tranche storage tranche = pools[poolId].tranches[trancheId];
        return tranche.token;
    }

    function getLiquidityPool(uint64 poolId, bytes16 trancheId, address currency) public view returns (address) {
        return pools[poolId].tranches[trancheId].liquidityPools[currency];
    }

    function isAllowedAsPoolCurrency(uint64 poolId, address currencyAddress) public view returns (bool) {
        uint128 currency = currencyAddressToId[currencyAddress];
        require(currency != 0, "PoolManager/unknown-currency"); // Currency index on the Centrifuge side should start at 1
        require(pools[poolId].allowedCurrencies[currencyAddress], "PoolManager/pool-currency-not-allowed");
        return true;
    }
}
