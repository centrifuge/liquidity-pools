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
 * A collection of handlers that interact with the Liquidity Pool
 * NOTE: The following external functions have been skipped
 * - requestDepositWithPermit
 * - vault_emitDepositClaimable
 * - vault_emitRedeemClaimable
 * - vault_file
 */
abstract contract VaultFunctions is BaseTargetFunctions, Properties {
    /// @dev Get the balance of the current token and actor
    function _getTokenAndBalanceForVault() internal view returns (uint256) {
        // Token
        uint256 amt = token.balanceOf(actor);

        return amt;
    }

    // === REQUEST === //
    function vault_requestDeposit(uint256 assets) public {
        assets = between(assets, 0, _getTokenAndBalanceForVault());

        token.approve(address(vault), assets);
        address to = actor; // NOTE: We transfer to self for now

        // B4 Balances
        uint256 balanceB4 = token.balanceOf(actor);
        uint256 balanceOfEscrowB4 = token.balanceOf(address(escrow));

        bool hasReverted;
        try vault.requestDeposit(assets, to, actor) {
            // TF-1
            sumOfDepositRequests[address(token)] += assets;

            requestDepositAssets[actor][address(token)] += assets;
        } catch {
            hasReverted = true;
        }

        // If not member
        (bool isMember,) = restrictionManager.isMember(address(trancheToken), actor);
        if (!isMember) {
            t(hasReverted, "LP-1 Must Revert");
        }

        if (
            restrictionManager.isFrozen(address(trancheToken), actor) == true
                || restrictionManager.isFrozen(address(trancheToken), to) == true
        ) {
            t(hasReverted, "LP-2 Must Revert");
        }

        if (!poolManager.isAllowedAsset(poolId, address(token))) {
            // TODO: Ensure this works via actor switch
            t(hasReverted, "LP-3 Must Revert");
        }

        // After Balances and Checks
        uint256 balanceAfter = token.balanceOf(actor);
        uint256 balanceOfEscrowAfter = token.balanceOf(address(escrow));

        // NOTE: We only enforce the check if the tx didn't revert
        if (!hasReverted) {
            // Extra check
            // NOTE: Unchecked so we get broken property and debug faster
            uint256 deltaUser = balanceB4 - balanceAfter;
            uint256 deltaEscrow = balanceOfEscrowAfter - balanceOfEscrowB4;

            if (RECON_EXACT_BAL_CHECK) {
                eq(deltaUser, assets, "Extra LP-1");
            }

            eq(deltaUser, deltaEscrow, "7540-11");
        }
    }

    function vault_requestRedeem(uint256 shares) public {
        address to = actor; // TODO: donation / changes

        // B4 Balances
        uint256 balanceB4 = trancheToken.balanceOf(actor);
        uint256 balanceOfEscrowB4 = trancheToken.balanceOf(address(escrow));

        trancheToken.approve(address(vault), shares);

        bool hasReverted;
        try vault.requestRedeem(shares, to, actor) {
            sumOfRedeemRequests[address(trancheToken)] += shares; // E-2
            requestRedeemShares[actor][address(trancheToken)] += shares;
        } catch {
            hasReverted = true;
        }

        if (
            restrictionManager.isFrozen(address(trancheToken), actor) == true
                || restrictionManager.isFrozen(address(trancheToken), to) == true
        ) {
            t(hasReverted, "LP-2 Must Revert");
        }

        // After Balances and Checks
        uint256 balanceAfter = trancheToken.balanceOf(actor);
        uint256 balanceOfEscrowAfter = trancheToken.balanceOf(address(escrow));

        // NOTE: We only enforce the check if the tx didn't revert
        if (!hasReverted) {
            // Extra check
            unchecked {
                uint256 deltaUser = balanceB4 - balanceAfter;
                uint256 deltaEscrow = balanceOfEscrowAfter - balanceOfEscrowB4;
                emit DebugNumber(deltaUser);
                emit DebugNumber(shares);
                emit DebugNumber(deltaEscrow);

                if (RECON_EXACT_BAL_CHECK) {
                    eq(deltaUser, shares, "Extra LP-1");
                }

                eq(deltaUser, deltaEscrow, "7540-12");
            }
        }
    }

    // === CANCEL === //

    function vault_cancelDepositRequest() public {
        vault.cancelDepositRequest(REQUEST_ID, actor);
    }

    function vault_cancelRedeemRequest() public {
        vault.cancelRedeemRequest(REQUEST_ID, actor);
    }

    function vault_claimCancelDepositRequest() public {
        address to = actor; // NOTE: We transfer to self for now

        uint256 assets = vault.claimCancelDepositRequest(REQUEST_ID, to, actor);
        sumOfClaimedDepositCancelations[address(token)] += assets;
    }

    function vault_claimCancelRedeemRequest() public {
        address to = actor; // NOTE: We transfer to self for now

        uint256 shares = vault.claimCancelRedeemRequest(REQUEST_ID, to, actor);
        sumOfClaimedRedeemCancelations[address(trancheToken)] += shares;
    }

    function vault_deposit(uint256 assets) public {
        // Bal b4
        uint256 trancheUserB4 = trancheToken.balanceOf(actor);
        uint256 trancheEscrowB4 = trancheToken.balanceOf(address(escrow));

        uint256 shares = vault.deposit(assets, address(this));

        // Processed Deposit | E-2 | Global-1
        sumOfClaimedDeposits[address(trancheToken)] += shares;

        // Bal after
        uint256 trancheUserAfter = trancheToken.balanceOf(actor);
        uint256 trancheEscrowAfter = trancheToken.balanceOf(address(escrow));

        // Extra check | // TODO: This math will prob overflow
        // NOTE: Unchecked so we get broken property and debug faster
        unchecked {
            uint256 deltaUser = trancheUserAfter - trancheUserB4; // B4 - after -> They pay
            uint256 deltaEscrow = trancheEscrowB4 - trancheEscrowAfter; // After - B4 -> They gain
            emit DebugNumber(deltaUser);
            emit DebugNumber(assets);
            emit DebugNumber(deltaEscrow);

            if (RECON_EXACT_BAL_CHECK) {
                eq(deltaUser, assets, "Extra LP-2");
            }

            eq(deltaUser, deltaEscrow, "7540-13");
        }
    }

    // Given a random value, see if the other one would yield more shares or lower cost
    // Not only check view
    // Also do it and test it via revert test
    // TODO: Mint Deposit Arb Test
    // TODO: Withdraw Redeem Arb Test

    // TODO: See how these go
    // TODO: Receiver -> Not this
    function vault_mint(uint256 shares) public {
        address to = actor; // TODO: donation / changes

        // Bal b4
        uint256 trancheUserB4 = trancheToken.balanceOf(actor);
        uint256 trancheEscrowB4 = trancheToken.balanceOf(address(escrow));

        vault.mint(shares, to);

        // Processed Deposit | E-2
        sumOfClaimedDeposits[address(trancheToken)] += shares;

        // Bal after
        uint256 trancheUserAfter = trancheToken.balanceOf(actor);
        uint256 trancheEscrowAfter = trancheToken.balanceOf(address(escrow));

        // Extra check | // TODO: This math will prob overflow
        // NOTE: Unchecked so we get broken property and debug faster
        unchecked {
            uint256 deltaUser = trancheUserAfter - trancheUserB4; // B4 - after -> They pay
            uint256 deltaEscrow = trancheEscrowB4 - trancheEscrowAfter; // After - B4 -> They gain
            emit DebugNumber(deltaUser);
            emit DebugNumber(shares);
            emit DebugNumber(deltaEscrow);

            if (RECON_EXACT_BAL_CHECK) {
                eq(deltaUser, shares, "Extra LP-2");
            }

            eq(deltaUser, deltaEscrow, "7540-13");
        }
    }

    // TODO: Params
    function vault_redeem(uint256 shares) public {
        address to = actor; // TODO: donation / changes

        // Bal b4
        uint256 tokenUserB4 = token.balanceOf(actor);
        uint256 tokenEscrowB4 = token.balanceOf(address(escrow));

        uint256 assets = vault.redeem(shares, actor, to);

        // E-1
        sumOfClaimedRedemptions[address(token)] += assets;

        // Bal after
        uint256 tokenUserAfter = token.balanceOf(actor);
        uint256 tokenEscrowAfter = token.balanceOf(address(escrow));

        // Extra check | // TODO: This math will prob overflow
        // NOTE: Unchecked so we get broken property and debug faster
        unchecked {
            uint256 deltaUser = tokenUserAfter - tokenUserB4;

            // TODO: NOTE FOT extra, verifies the transfer amount matches the returned amount
            t(deltaUser == assets, "FoT-1");

            uint256 deltaEscrow = tokenEscrowB4 - tokenEscrowAfter;
            emit DebugNumber(deltaUser);
            emit DebugNumber(shares);
            emit DebugNumber(deltaEscrow);

            if (RECON_EXACT_BAL_CHECK) {
                eq(deltaUser, shares, "Extra LP-3");
            }

            eq(deltaUser, deltaEscrow, "7540-14");
        }
    }

    // TODO: Params
    function vault_withdraw(uint256 assets) public {
        address to = actor; // TODO: donation / changes

        // Bal b4
        uint256 tokenUserB4 = token.balanceOf(actor);
        uint256 tokenEscrowB4 = token.balanceOf(address(escrow));

        uint256 shares = vault.withdraw(assets, actor, to);

        // E-1
        sumOfClaimedRedemptions[address(token)] += assets;

        // Bal after
        uint256 tokenUserAfter = token.balanceOf(actor);
        uint256 tokenEscrowAfter = token.balanceOf(address(escrow));

        // Extra check | // TODO: This math will prob overflow
        // NOTE: Unchecked so we get broken property and debug faster
        unchecked {
            uint256 deltaUser = tokenUserAfter - tokenUserB4;
            uint256 deltaEscrow = tokenEscrowB4 - tokenEscrowAfter;
            emit DebugNumber(deltaUser);
            emit DebugNumber(assets);
            emit DebugNumber(deltaEscrow);

            if (RECON_EXACT_BAL_CHECK) {
                eq(deltaUser, assets, "Extra LP-3");
            }

            eq(deltaUser, deltaEscrow, "7540-14");
        }
    }
}
