// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.26;

// Recon Deps
import {BaseTargetFunctions} from "@chimera/BaseTargetFunctions.sol";
import {Properties} from "./Properties.sol";
import {vm} from "@chimera/Hevm.sol";

// Dependencies
import {ERC20} from "src/token/ERC20.sol";
import {ERC7540Vault} from "src/ERC7540Vault.sol";

// Component
import {TrancheTokenFunctions} from "./targets/TrancheTokenFunctions.sol";
import {GatewayMockFunctions} from "./targets/GatewayMockFunctions.sol";
import {RestrictionManagerFunctions} from "./targets/RestrictionManagerFunctions.sol";
import {VaultFunctions} from "./targets/VaultFunctions.sol";
import {PoolManagerFunctions} from "./targets/PoolManagerFunctions.sol";
import {VaultCallbacks} from "./targets/VaultCallbacks.sol";
import {RouterFunctions} from "./targets/RouterFunctions.sol";

abstract contract TargetFunctions is
    BaseTargetFunctions,
    Properties,
    TrancheTokenFunctions,
    GatewayMockFunctions,
    RestrictionManagerFunctions,
    VaultFunctions,
    PoolManagerFunctions,
    VaultCallbacks,
    RouterFunctions
{
    /**
     * TODO: Port Over tranche, liquidity pool stuff
     *
     *
     */

    /**
     * INVESTOR FUNCTIONS
     */
    function invariant_doesTokenGetDeployed() public returns (bool) {
        if (RECON_TOGGLE_CANARY_TESTS) {
            return allTokens.length < 10;
        }

        return true;
    }

    function invariant_doesTranchesGetDeployed() public returns (bool) {
        if (RECON_TOGGLE_CANARY_TESTS) {
            return trancheTokens.length < 10;
        }

        return true;
    }

    function invariant_doesVaultsGetDeployed() public returns (bool) {
        if (RECON_TOGGLE_CANARY_TESTS) {
            return vaults.length < 10;
        }

        return true;
    }
}
