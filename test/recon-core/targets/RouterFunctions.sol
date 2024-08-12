// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.26;

// Recon Deps
import {BaseTargetFunctions} from "@chimera/BaseTargetFunctions.sol";
import {Properties} from "../Properties.sol";
import {vm} from "@chimera/Hevm.sol";

// Dependencies
import {ERC20} from "src/token/ERC20.sol";
import {ERC7540Vault} from "src/ERC7540Vault.sol";

/**
 * A collection of handlers that interact with the Centrifuge Router
 */
abstract contract RouterFunctions is BaseTargetFunctions, Properties {
    // === Enable lock deposit request === //
    function router_enableLockDepositRequest(uint256 assets) public {
        assets = between(assets, 0, _getTokenAndBalanceForVault());

        token.approve(address(router), assets);

        // B4 Balances
        uint256 balanceB4 = token.balanceOf(actor);
        uint256 balanceOfRouterEscrowB4 = token.balanceOf(address(routerEscrow));

        bool hasReverted;
        try router.enableLockDepositRequest(address(vault), assets) {
            // TODO: add shadow variables
        } catch {
            hasReverted = true;
        }

        if (!poolManager.isAllowedAsset(poolId, address(token))) {
            // TODO: Ensure this works via actor switch
            t(hasReverted, "Router-1 Must Revert");
        }

        // After Balances and Checks
        uint256 balanceAfter = token.balanceOf(actor);
        uint256 balanceOfRouterEscrowAfter = token.balanceOf(address(routerEscrow));

        // NOTE: We only enforce the check if the tx didn't revert
        if (!hasReverted) {
            // Extra check
            // NOTE: Unchecked so we get broken property and debug faster
            uint256 deltaUser = balanceB4 - balanceAfter;
            uint256 deltaRouterEscrow = balanceOfRouterEscrowAfter - balanceOfRouterEscrowB4;

            if (RECON_EXACT_BAL_CHECK) {
                eq(deltaUser, assets, "Router-2");
            }

            eq(deltaUser, deltaRouterEscrow, "Router-3");
        }
    }
}
