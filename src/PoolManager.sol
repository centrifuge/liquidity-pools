// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import {TrancheTokenFactoryLike, RestrictionManagerFactoryLike, LiquidityPoolFactoryLike} from "./util/Factory.sol";
import {TrancheTokenLike} from "./token/Tranche.sol";
import {RestrictionManagerLike} from "./token/RestrictionManager.sol";
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
    mapping(bytes16 trancheId => Tranche) tranches;
    mapping(address currencyAddress => bool) allowedCurrencies;
}

/// @dev Each Centrifuge pool is associated to 1 or more tranches
struct Tranche {
    address token;
    // important: the decimals of the leading pool currency. Liquidity Pool shares have to be denomatimated with the same precision.
    uint8 decimals;
    uint256 createdAt;
    string tokenName;
    string tokenSymbol;
    /// @dev Each tranche can have multiple liquidity pools deployed,
    /// each linked to a unique investment currency (asset)
    mapping(address currencyAddress => address liquidityPool) liquidityPools;
}

/// @title  Pool Manager
/// @notice This contract manages which pools & tranches exist,
///         as well as managing allowed pool currencies, and incoming and outgoing transfers.
contract PoolManager is Auth {
    uint8 internal constant MAX_DECIMALS = 18;

    EscrowLike public immutable escrow;
    LiquidityPoolFactoryLike public immutable liquidityPoolFactory;
    RestrictionManagerFactoryLike public immutable restrictionManagerFactory;
    TrancheTokenFactoryLike public immutable trancheTokenFactory;

    GatewayLike public gateway;
    InvestmentManagerLike public investmentManager;

    mapping(uint64 poolId => Pool) public pools;

    /// @dev Chain agnostic currency id -> evm currency address and reverse mapping
    mapping(uint128 currencyId => address) public currencyIdToAddress;
    mapping(address => uint128 currencyId) public currencyAddressToId;

    // --- Events ---
    event File(bytes32 indexed what, address data);
    event AddPool(uint64 indexed poolId);
    event AllowInvestmentCurrency(uint128 indexed currency, uint64 indexed poolId);
    event AddTranche(uint64 indexed poolId, bytes16 indexed trancheId);
    event DeployTranche(uint64 indexed poolId, bytes16 indexed trancheId, address indexed token);
    event AddCurrency(uint128 indexed currency, address indexed currencyAddress);
    event DeployLiquidityPool(uint64 indexed poolId, bytes16 indexed trancheId, address indexed liquidityPool);
    event TransferCurrency(address indexed currencyAddress, bytes32 indexed recipient, uint128 amount);
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
        else revert("PoolManager/file-unrecognized-param");
        emit File(what, data);
    }

    // --- Outgoing message handling ---
    function transfer(address currencyAddress, bytes32 recipient, uint128 amount) public {
        uint128 currency = currencyAddressToId[currencyAddress];
        require(currency != 0, "PoolManager/unknown-currency");

        // Transfer the currency amount from user to escrow (lock currency in escrow)
        // Checks actual balance difference to support fee-on-transfer tokens
        uint256 preBalance = IERC20(currencyAddress).balanceOf(address(escrow));
        SafeTransferLib.safeTransferFrom(currencyAddress, msg.sender, address(escrow), amount);
        uint256 postBalance = IERC20(currencyAddress).balanceOf(address(escrow));
        uint128 transferredAmount = _toUint128(postBalance - preBalance);

        gateway.transfer(currency, msg.sender, recipient, transferredAmount);
        emit TransferCurrency(currencyAddress, recipient, transferredAmount);
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

        emit TransferTrancheTokensToCentrifuge(poolId, trancheId, destinationAddress, amount);
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

        emit TransferTrancheTokensToEVM(poolId, trancheId, destinationChainId, destinationAddress, amount);
    }

    // --- Incoming message handling ---
    /// @notice    New pool details from an existing Centrifuge pool are added.
    /// @dev       The function can only be executed by the gateway contract.
    function addPool(uint64 poolId) public onlyGateway {
        Pool storage pool = pools[poolId];
        require(pool.createdAt == 0, "PoolManager/pool-already-added");
        pool.poolId = poolId;
        pool.createdAt = block.timestamp;
        emit AddPool(poolId);
    }

    /// @notice     Centrifuge pools can support multiple currencies for investing. this function adds a new supported currency to the pool details.
    ///             Adding new currencies allow the creation of new liquidity pools for the underlying Centrifuge pool.
    /// @dev        The function can only be executed by the gateway contract.
    function allowInvestmentCurrency(uint64 poolId, uint128 currency) public onlyGateway {
        Pool storage pool = pools[poolId];
        require(pool.createdAt != 0, "PoolManager/invalid-pool");

        address currencyAddress = currencyIdToAddress[currency];
        require(currencyAddress != address(0), "PoolManager/unknown-currency");

        pools[poolId].allowedCurrencies[currencyAddress] = true;
        emit AllowInvestmentCurrency(currency, poolId);
    }

    /// @notice     New tranche details from an existing Centrifuge pool are added.
    /// @dev        The function can only be executed by the gateway contract.
    function addTranche(
        uint64 poolId,
        bytes16 trancheId,
        string memory tokenName,
        string memory tokenSymbol,
        uint8 decimals
    ) public onlyGateway {
        require(decimals <= MAX_DECIMALS, "PoolManager/too-many-tranche-token-decimals");

        Pool storage pool = pools[poolId];
        require(pool.createdAt != 0, "PoolManager/invalid-pool");
        Tranche storage tranche = pool.tranches[trancheId];
        require(tranche.createdAt == 0, "PoolManager/tranche-already-exists");

        tranche.decimals = decimals;
        tranche.tokenName = tokenName;
        tranche.tokenSymbol = tokenSymbol;
        tranche.createdAt = block.timestamp;

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

        trancheToken.file("name", tokenName);
        trancheToken.file("symbol", tokenSymbol);
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

    /// @notice A global chain agnostic currency index is maintained on Centrifuge. This function maps a currency from the Centrifuge index to its corresponding address on the evm chain.
    ///         The chain agnostic currency id has to be used to pass currency information to the Centrifuge.
    /// @dev    This function can only be executed by the gateway contract.
    function addCurrency(uint128 currency, address currencyAddress) public onlyGateway {
        // Currency index on the Centrifuge side should start at 1
        require(currency != 0, "PoolManager/currency-id-has-to-be-greater-than-0");
        require(currencyIdToAddress[currency] == address(0), "PoolManager/currency-id-in-use");
        require(currencyAddressToId[currencyAddress] == 0, "PoolManager/currency-address-in-use");
        require(IERC20(currencyAddress).decimals() <= MAX_DECIMALS, "PoolManager/too-many-currency-decimals");

        currencyIdToAddress[currency] = currencyAddress;
        currencyAddressToId[currencyAddress] = currency;

        // Enable taking the currency out of escrow in case of redemptions
        EscrowLike(escrow).approve(currencyAddress, investmentManager.userEscrow(), type(uint256).max);

        // Enable taking the currency out of escrow in case of decrease invest orders
        EscrowLike(escrow).approve(currencyAddress, address(investmentManager), type(uint256).max);

        emit AddCurrency(currency, currencyAddress);
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
            RestrictionManagerLike(address(trancheToken.restrictionManager())).hasMember(destinationAddress),
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

        address[] memory restrictionManagerWards = new address[](1);
        restrictionManagerWards[0] = address(this);

        address token = trancheTokenFactory.newTrancheToken(
            poolId, trancheId, tranche.tokenName, tranche.tokenSymbol, tranche.decimals, trancheTokenWards
        );
        address restrictionManager = restrictionManagerFactory.newRestrictionManager(token, restrictionManagerWards);
        TrancheTokenLike(token).file("restrictionManager", restrictionManager);

        tranche.token = token;
        emit DeployTranche(poolId, trancheId, token);
        return token;
    }

    function deployLiquidityPool(uint64 poolId, bytes16 trancheId, address currency) public returns (address) {
        Tranche storage tranche = pools[poolId].tranches[trancheId];
        require(tranche.token != address(0), "PoolManager/tranche-does-not-exist"); // Tranche must have been added
        require(isAllowedAsPoolCurrency(poolId, currency), "PoolManager/currency-not-supported"); // Currency must be supported by pool

        address liquidityPool = tranche.liquidityPools[currency];
        require(liquidityPool == address(0), "PoolManager/liquidityPool-already-deployed");

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

        emit DeployLiquidityPool(poolId, trancheId, liquidityPool);
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

    /// @dev    Safe type conversion from uint256 to uint128. Revert if value is too big to be stored with uint128. Avoid data loss.
    /// @return value - safely converted without data loss
    function _toUint128(uint256 _value) internal pure returns (uint128 value) {
        if (_value > type(uint128).max) {
            revert("InvestmentManager/uint128-overflow");
        } else {
            value = uint128(_value);
        }
    }
}
