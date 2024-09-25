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
            sumOfLockedDepositRequests[address(token)] += assets;
        } catch {
            hasReverted = true;
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
                eq(deltaUser, assets, "Router-x");
            }

            eq(deltaUser, deltaRouterEscrow, "Router-x");
        }
    }

    // === Lock deposit request === //
    // TODO

    // === Executed locked deposit request === //
    function router_unlockDepositRequest() public {
        uint256 balanceB4 = token.balanceOf(actor);
        uint256 balanceOfRouterEscrowB4 = token.balanceOf(address(routerEscrow));
        uint256 lockedRequestB4 = router.lockedRequests(actor, address(vault));

        bool hasReverted;
        try router.unlockDepositRequest(address(vault), actor) {
            sumOfUnlockedDepositRequests[address(token)] += lockedRequestB4;
        } catch {
            hasReverted = true;
        }

        // After Balances and Checks
        uint256 balanceAfter = token.balanceOf(actor);
        uint256 balanceOfRouterEscrowAfter = token.balanceOf(address(routerEscrow));
        uint256 lockedRequestAfter = router.lockedRequests(actor, address(vault));

        // NOTE: We only enforce the check if the tx didn't revert
        if (!hasReverted) {
            uint256 deltaUser = balanceB4 - balanceAfter;
            uint256 deltaRouterEscrow = balanceOfRouterEscrowAfter - balanceOfRouterEscrowB4;

            if (RECON_EXACT_BAL_CHECK) {
                eq(deltaUser, lockedRequestB4, "Router-x");
            }

            eq(deltaRouterEscrow, lockedRequestB4, "Router-x");
            eq(lockedRequestAfter, 0, "Router-x");
        }
    }

    // === Executed locked deposit request === //
    function router_executeLockedDepositRequest() public {
        uint256 balanceOfEscrowB4 = token.balanceOf(address(escrow));
        uint256 balanceOfRouterEscrowB4 = token.balanceOf(address(routerEscrow));
        uint256 lockedRequestB4 = router.lockedRequests(actor, address(vault));

        bool hasReverted;
        try router.executeLockedDepositRequest(address(vault), actor, 0) {
            sumOfExecutedLockedDepositRequests[address(token)] += lockedRequestB4;
        } catch {
            hasReverted = true;
        }

        if (!poolManager.isAllowedAsset(poolId, address(token))) {
            // TODO: Ensure this works via actor switch
            t(hasReverted, "Router-x Must Revert");
        }

        // After Balances and Checks
        uint256 balanceOfEscrowAfter = token.balanceOf(address(escrow));
        uint256 balanceOfRouterEscrowAfter = token.balanceOf(address(routerEscrow));
        uint256 lockedRequestAfter = router.lockedRequests(actor, address(vault));

        // NOTE: We only enforce the check if the tx didn't revert
        if (!hasReverted) {
            uint256 deltaEscrow = balanceOfEscrowAfter - balanceOfEscrowB4;
            uint256 deltaRouterEscrow = balanceOfRouterEscrowB4 - balanceOfRouterEscrowAfter;

            eq(deltaEscrow, lockedRequestB4, "Router-x");
            eq(deltaRouterEscrow, lockedRequestB4, "Router-x");
            eq(lockedRequestAfter, 0, "Router-x");
        }
    }

    // === request Deposit === //
    function router_requestDeposit(uint256 assets) public {
        address owner = actor;
        address controller = actor; // TODO: test with different address wen multi-actor supported

        uint256 balanceOfEscrowB4 = token.balanceOf(address(escrow));
        uint256 balanceOfRouterEscrowB4 = token.balanceOf(address(routerEscrow));
        uint256 balanceOfOwnerB4 = token.balanceOf(owner);
        assets = between(assets, 0, _getTokenAndBalanceForVault());

        bool hasReverted;

        token.approve(address(vault), assets); // owner = self -> allow to transfer tokens - need to test edge cacse
            // without allowance

        try router.requestDeposit(address(vault), assets, controller, owner, 0) {
            // TODO: test topup
            sumOfDepositRequestsRouter[address(token)] += assets;
            requestDepositAssets[actor][address(token)] += assets;
        } catch {
            hasReverted = true;
        }

        if (!poolManager.isAllowedAsset(poolId, address(token))) {
            // TODO: Ensure this works via actor switch
            t(hasReverted, "Router-x Must Revert");
        }

        // If not member
        (bool isMember,) = restrictionManager.isMember(address(trancheToken), controller);
        if (!isMember) {
            t(hasReverted, "LP-1 Must Revert");
        }
        if (restrictionManager.isFrozen(address(trancheToken), controller) == true) {
            t(hasReverted, "LP-2 Must Revert");
        }
        if (!poolManager.isAllowedAsset(poolId, address(token))) {
            t(hasReverted, "LP-3 Must Revert");
        }

        // After Balances and Checks
        uint256 balanceOfEscrowAfter = token.balanceOf(address(escrow));
        uint256 balanceOfOwnerAfter = token.balanceOf(owner);
        uint256 balanceOfRouterEscrowAfter = token.balanceOf(address(routerEscrow));

        // NOTE: We only enforce the check if the tx didn't revert
        if (!hasReverted) {
            uint256 deltaEscrow = balanceOfEscrowAfter - balanceOfEscrowB4;
            uint256 deltaOwner = balanceOfOwnerB4 - balanceOfOwnerAfter;
            uint256 deltaRouterEscrow = balanceOfRouterEscrowB4 - balanceOfRouterEscrowAfter;

            eq(deltaEscrow, assets, "Router-x");
            eq(deltaOwner, assets, "Router-x");
            eq(deltaRouterEscrow, 0, "Router-x");
        }
    }

    // TODO: once we have multi actor support, include receiver != controller case
    function router_claimDeposit(address sender) public {
        // Bal b4
        uint256 trancheUserB4 = trancheToken.balanceOf(actor);
        uint256 trancheEscrowB4 = trancheToken.balanceOf(address(escrow));
        uint256 shares = vault.maxMint(address(actor));

        bool hasReverted;
        vm.prank(sender);
        try router.claimDeposit(address(vault), address(actor), address(actor)) {
            // Processed Deposit | E-2 | Global-1
            sumOfClaimedDeposits[address(trancheToken)] += shares;
        } catch {
            hasReverted = true;
        }

        if (!router.isEnabled(address(vault), address(actor)) && address(actor) != sender) {
            t(hasReverted, "Router-x Must Revert");
        }

        // Bal after
        uint256 trancheUserAfter = trancheToken.balanceOf(actor);
        uint256 trancheEscrowAfter = trancheToken.balanceOf(address(escrow));

        // NOTE: We only enforce the check if the tx didn't revert
        if (!hasReverted) {
            unchecked {
                uint256 deltaUser = trancheUserAfter - trancheUserB4; // B4 - after -> They pay
                uint256 deltaEscrow = trancheEscrowB4 - trancheEscrowAfter; // After - B4 -> They gain
                emit DebugNumber(deltaUser);
                emit DebugNumber(deltaEscrow);

                eq(deltaUser, deltaEscrow, "Router-x");
            }
        }
    }

    // === Cancel Deposit Request === //
    function router_cancelDepositRequest() public {
        uint256 balanceB4 = token.balanceOf(actor);
        uint256 balanceOfRouterEscrowB4 = token.balanceOf(address(routerEscrow));
        uint256 lockedRequestB4 = router.lockedRequests(actor, address(vault));

        bool hasReverted;
        try router.cancelDepositRequest(address(vault), 0) {
            sumOfCancelledDepositRequests[address(token)] += lockedRequestB4;
        } catch {
            hasReverted = true;
        }

        // After Balances and Checks
        uint256 balanceAfter = token.balanceOf(actor);
        uint256 balanceOfRouterEscrowAfter = token.balanceOf(address(routerEscrow));
        uint256 lockedRequestAfter = router.lockedRequests(actor, address(vault));

        if (!hasReverted) {
            uint256 deltaUser = balanceB4 - balanceAfter;
            uint256 deltaRouterEscrow = balanceOfRouterEscrowAfter - balanceOfRouterEscrowB4;

            if (RECON_EXACT_BAL_CHECK) {
                eq(deltaUser, lockedRequestB4, "Router-x");
            }

            eq(deltaRouterEscrow, lockedRequestB4, "Router-x");
            eq(lockedRequestAfter, 0, "Router-x");
        }
    }
}
