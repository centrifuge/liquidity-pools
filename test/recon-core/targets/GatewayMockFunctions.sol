// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.26;

// Recon Deps
import {BaseTargetFunctions} from "@chimera/BaseTargetFunctions.sol";
import {Properties} from "../Properties.sol";
import {vm} from "@chimera/Hevm.sol";

// Src Deps | For cycling of values
import {ERC7540Vault} from "src/ERC7540Vault.sol";
import {ERC20} from "src/token/ERC20.sol";
import {Tranche} from "src/token/Tranche.sol";
import {RestrictionManager} from "src/token/RestrictionManager.sol";
import {RestrictionUpdate} from "src/interfaces/token/IRestrictionManager.sol";
import {CastLib} from "src/libraries/CastLib.sol";

// @dev A way to separately code and maintain a mocked implementation of `Gateway`
// Based on
// `Gateway.handle(bytes calldata message)`
/**
 * - deployNewTokenPoolAndTranche Core function that deploys a Liquidity Pool
 *     - poolManager_addAsset
 */
abstract contract GatewayMockFunctions is BaseTargetFunctions, Properties {
    using CastLib for *;

    // Deploy new Asset
    // Add Asset to Pool -> Also deploy Tranche

    bool hasDoneADeploy;

    // Pool ID = Pool ID
    // Asset ID
    // Tranche ID

    // Basically the real complete setup
    function deployNewTokenPoolAndTranche(uint8 decimals, uint256 initialMintPerUsers)
        public
        returns (address newToken, address newTranche, address newVault)
    {
        // NOTE: TEMPORARY
        require(!hasDoneADeploy); // This bricks the function for this one for Medusa
        // Meaning we only deploy one token, one Pool, one tranche

        if (RECON_USE_SINGLE_DEPLOY) {
            hasDoneADeploy = true;
        }

        if (RECON_USE_HARDCODED_DECIMALS) {
            decimals = 18;
        }

        initialMintPerUsers = 1_000_000e18;
        // NOTE END TEMPORARY

        decimals = decimals % RECON_MODULO_DECIMALS;
        /// @audit NOTE: This works because we only deploy once!!

        newToken = addToken(decimals, initialMintPerUsers);
        {
            CURRENCY_ID += 1;
            poolManager_addAsset(CURRENCY_ID, address(newToken));
        }

        {
            POOL_ID += 1;
            poolManager_addPool(POOL_ID);
            poolManager_allowAsset(POOL_ID, CURRENCY_ID);
        }

        {
            // TODO: QA: Custom Names
            string memory name = "Tranche";
            string memory symbol = "T1";

            // TODO: Ask if we should customize decimals and permissions here
            poolManager_addTranche(POOL_ID, TRANCHE_ID, name, symbol, 18, address(restrictionManager));
        }

        newTranche = poolManager_deployTranche(POOL_ID, TRANCHE_ID);

        newVault = poolManager_deployVault(POOL_ID, TRANCHE_ID, address(newToken));

        // NOTE: Add to storage! So this will be called by other functions
        // NOTE: This sets the actors
        // We will cycle them through other means
        // NOTE: These are all tightly coupled
        // First step of uncoupling is to simply store all of them as a setting
        // So we can have multi deploys
        // And do parallel checks

        // O(n)
        // Basically switch on new deploy
        // And track all historical

        // O(n*m)
        // Second Step is to store permutations
        // Which means we have to switch on all permutations on all checks

        vault = ERC7540Vault(newVault);
        token = ERC20(newToken);
        trancheToken = Tranche(newTranche);
        restrictionManager = RestrictionManager(address(trancheToken.hook()));

        trancheId = TRANCHE_ID;
        poolId = POOL_ID;
        currencyId = CURRENCY_ID;

        // NOTE: Iplicit return
    }

    // Create a Asset
    // Add it to All Pools

    // Step 2
    function poolManager_addAsset(uint128 currencyId, address currencyAddress) public {
        poolManager.addAsset(currencyId, currencyAddress);

        // Only if success full
        tokenToCurrencyId[currencyAddress] = currencyId;
        currencyIdToToken[currencyId] = currencyAddress;
    }

    // Step 5
    function poolManager_allowAsset(uint64 poolId, uint128 currencyId) public {
        poolManager.allowAsset(poolId, currencyId);
    }

    // Step 3
    function poolManager_addPool(uint64 poolId) public {
        poolManager.addPool(poolId);
    }

    // Step 4
    function poolManager_addTranche(
        uint64 poolId,
        bytes16 trancheId,
        string memory tokenName,
        string memory tokenSymbol,
        uint8 decimals,
        address hook
    ) public {
        poolManager.addTranche(poolId, trancheId, tokenName, tokenSymbol, decimals, address(restrictionManager));
    }

    // Step 9
    function poolManager_deployTranche(uint64 poolId, bytes16 trancheId) public returns (address) {
        return poolManager.deployTranche(poolId, trancheId);
    }

    // Step 10
    function poolManager_deployVault(uint64 poolId, bytes16 trancheId, address currency) public returns (address) {
        return poolManager.deployVault(poolId, trancheId, currency);
    }

    /**
     * NOTE: All of these are implicitly clamped!
     */
    function poolManager_updateMember(uint64 validUntil) public {
        poolManager.updateRestriction(
            poolId, trancheId, abi.encodePacked(uint8(RestrictionUpdate.UpdateMember), actor.toBytes32(), validUntil)
        );
    }

    // TODO: Price is capped at u64 to test overflows
    function poolManager_updateTranchePrice(uint64 price, uint64 computedAt) public {
        poolManager.updateTranchePrice(poolId, trancheId, currencyId, price, computedAt);
    }

    function poolManager_updateTrancheMetadata(string memory tokenName, string memory tokenSymbol) public {
        poolManager.updateTrancheMetadata(poolId, trancheId, tokenName, tokenSymbol);
    }

    function poolManager_freeze() public {
        poolManager.updateRestriction(
            poolId, trancheId, abi.encodePacked(uint8(RestrictionUpdate.Freeze), actor.toBytes32())
        );
    }

    function poolManager_unfreeze() public {
        poolManager.updateRestriction(
            poolId, trancheId, abi.encodePacked(uint8(RestrictionUpdate.Unfreeze), actor.toBytes32())
        );
    }

    function poolManager_disallowAsset() public {
        poolManager.disallowAsset(poolId, currencyId);
    }

    // TODO: Rely / Permissions
    // Only after all system is setup
    function root_scheduleRely(address target) public {
        root.scheduleRely(target);
    }

    function root_cancelRely(address target) public {
        root.cancelRely(target);
    }

    function addToken(uint8 decimals, uint256 initialMintPerUsers) public returns (address) {
        ERC20 newToken = new ERC20(decimals % RECON_MODULO_DECIMALS); // NOTE: we revert on <1 and >18

        allTokens.push(newToken);

        // TODO: If you have multi actors add them here
        newToken.mint(actor, initialMintPerUsers);

        return address(newToken);
    }

    function getMoreToken(uint8 tokenIndex, uint256 newTokenAmount) public {
        // Token Id
        ERC20 newToken = allTokens[tokenIndex % allTokens.length];

        // TODO: Consider minting to actors
        newToken.mint(address(this), newTokenAmount);
    }

    // Step 2 = poolManager_addAsset - GatewayMockFunctions
    // Step 3 = poolManager_addPool - GatewayMockFunctions
    // Step 4 = poolManager_addTranche - GatewayMockFunctions

    // Step 5 = poolManager_allowAsset - GatewayMockFunctions

    ////
    // A pool can belong to a tranche
    // A Vault can belong to a tranche and a currency

    // Step 6
    function deployTranche(uint64 poolId, bytes16 trancheId) public returns (address) {
        address newTranche = poolManager.deployTranche(poolId, trancheId);

        trancheTokens.push(newTranche);
    }

    // Step 7 is copied from step 5, ignore

    // Step 8, deploy the pool
    function deployVault(uint64 poolId, bytes16 trancheId, address currency) public returns (address) {
        address newVault = poolManager.deployVault(poolId, trancheId, currency);

        vaults.push(newVault);
    }

    // Extra 9 - Remove liquidity Pool
    function removeVault(uint64 poolId, bytes16 trancheId, address currency) public {
        // TODO: Pick one from above
        poolManager.removeVault(poolId, trancheId, currency);
    }
}

/// 2 Enter Functions
/// 2 Cancel Functions
/// 4 Callback functions
