// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.26;

import {BaseSetup} from "@chimera/BaseSetup.sol";
import {Escrow} from "src/Escrow.sol";
import {InvestmentManager} from "src/InvestmentManager.sol";
import {PoolManager} from "src/PoolManager.sol";
import {ERC7540Vault} from "src/ERC7540Vault.sol";
import {Root} from "src/Root.sol";
import {Tranche} from "src/token/Tranche.sol";
import {CentrifugeRouter} from "src/CentrifugeRouter.sol";

import {ERC7540VaultFactory} from "src/factories/ERC7540VaultFactory.sol";
import {TrancheFactory} from "src/factories/TrancheFactory.sol";

import {RestrictionManager} from "src/token/RestrictionManager.sol";
import {ERC20} from "src/token/ERC20.sol";

// Mocks
import {IRoot} from "src/interfaces/IRoot.sol";

// Storage
import {SharedStorage} from "./SharedStorage.sol";

abstract contract Setup is BaseSetup, SharedStorage {
    // Dependencies
    ERC7540VaultFactory vaultFactory;
    TrancheFactory trancheFactory;

    // Handled //
    Escrow public escrow; // NOTE: Restriction Manager will query it
    Escrow public routerEscrow;
    InvestmentManager investmentManager;
    PoolManager poolManager;
    CentrifugeRouter router;

    // TODO: CYCLE / Make it work for variable values
    ERC7540Vault vault;
    ERC20 token;
    Tranche trancheToken;
    address actor;
    RestrictionManager restrictionManager;

    bytes16 trancheId;
    uint64 poolId;
    uint64 currencyId;

    // MOCKS
    address centrifugeChain;
    IRoot root;

    // LP request ID is always 0
    uint256 REQUEST_ID = 0;

    // MOCK++
    fallback() external payable {
        // Basically we will receive `root.rely, etc..`
    }

    function setup() internal virtual override {
        // Put self so we can perform settings
        centrifugeChain = address(this);

        // Dependencies
        escrow = new Escrow(address(address(this)));
        routerEscrow = new Escrow(address(address(this)));
        root = new Root(address(escrow), 48 hours, address(this));
        vaultFactory = new ERC7540VaultFactory(address(root));
        trancheFactory = new TrancheFactory(address(root), address(this));
        restrictionManager = new RestrictionManager(address(root), address(this));

        poolManager = new PoolManager(address(escrow), address(vaultFactory), address(trancheFactory));
        poolManager.file("gateway", address(this));

        // Setup router
        router = new CentrifugeRouter(address(routerEscrow), address(this), address(poolManager));

        investmentManager = new InvestmentManager(address(root), address(escrow));

        investmentManager.file("gateway", address(this));
        investmentManager.file("poolManager", address(poolManager));
        investmentManager.rely(address(poolManager));
        investmentManager.rely(address(vaultFactory));

        poolManager.file("investmentManager", address(investmentManager));
        restrictionManager.rely(address(poolManager));

        // Setup Escrow Permissions
        escrow.rely(address(investmentManager));
        escrow.rely(address(poolManager));
        routerEscrow.rely(address(router));

        root.endorse(address(router));
        root.endorse(address(escrow));

        // Permissions on factories
        vaultFactory.rely(address(poolManager));
        trancheFactory.rely(address(poolManager));

        // TODO: Cycling of ERC7540 Vaults

        // Cycling of Actors
        actors.push(address(0x4c701));
        actors.push(address(0x4c702));
        actors.push(address(0x4c703));

        // Always use first actor until we have coverage that we expect
        actor = address(0x4c701);
    }

    /**
     * GLOBAL GHOST
     */
    mapping(address => Vars) internal _investorsGlobals;

    struct Vars {
        // See IM_1
        uint256 maxDepositPrice;
        uint256 minDepositPrice;
        // See IM_2
        uint256 maxRedeemPrice;
        uint256 minRedeemPrice;
    }

    function __globals() internal {
        (uint256 depositPrice, uint256 redeemPrice) = _getDepositAndRedeemPrice();

        // Conditionally Update max | Always works on zero
        _investorsGlobals[actor].maxDepositPrice = depositPrice > _investorsGlobals[actor].maxDepositPrice
            ? depositPrice
            : _investorsGlobals[actor].maxDepositPrice;
        _investorsGlobals[actor].maxRedeemPrice = redeemPrice > _investorsGlobals[actor].maxRedeemPrice
            ? redeemPrice
            : _investorsGlobals[actor].maxRedeemPrice;

        // Conditionally Update min
        // On zero we have to update anyway
        if (_investorsGlobals[actor].minDepositPrice == 0) {
            _investorsGlobals[actor].minDepositPrice = depositPrice;
        }
        if (_investorsGlobals[actor].minRedeemPrice == 0) {
            _investorsGlobals[actor].minRedeemPrice = redeemPrice;
        }

        // Conditional update after zero
        _investorsGlobals[actor].minDepositPrice = depositPrice < _investorsGlobals[actor].minDepositPrice
            ? depositPrice
            : _investorsGlobals[actor].minDepositPrice;
        _investorsGlobals[actor].minRedeemPrice = redeemPrice < _investorsGlobals[actor].minRedeemPrice
            ? redeemPrice
            : _investorsGlobals[actor].minRedeemPrice;
    }

    function _getDepositAndRedeemPrice() internal view returns (uint256, uint256) {
        (
            uint128 maxMint,
            uint128 maxWithdraw,
            uint256 depositPrice,
            uint256 redeemPrice,
            uint128 pendingDepositRequest,
            uint128 pendingRedeemRequest,
            uint128 claimableCancelDepositRequest,
            uint128 claimableCancelRedeemRequest,
            bool pendingCancelDepositRequest,
            bool pendingCancelRedeemRequest
        ) = investmentManager.investments(address(vault), address(actor));

        return (depositPrice, redeemPrice);
    }

    /// @dev Get the balance of the current token and actor
    function _getTokenAndBalanceForVault() internal view returns (uint256) {
        // Token
        uint256 amt = token.balanceOf(actor);

        return amt;
    }
}
