// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.26;

// Recon Deps
import {BaseTargetFunctions} from "@chimera/BaseTargetFunctions.sol";
import {Properties} from "../Properties.sol";
import {vm} from "@chimera/Hevm.sol";

// Dependencies
import {ERC20} from "src/token/ERC20.sol";
import {ERC7540Vault} from "src/ERC7540Vault.sol";
import {CentrifugeRouter} from "src/CentrifugeRouter.sol";

/**
 * A collection of handlers that interact with the CentrifugeRouter
 */
abstract contract CentrifugeRouterFunctions is BaseTargetFunctions, Properties {
    uint256 private constant REQUEST_ID = 0;

    function centrifugeRouter_requestDeposit(uint256 assets) public {
        assets = between(assets, 0, _getTokenAndBalanceForVault());

        token.approve(address(centrifugeRouter), assets);
        address to = actor; // Transfer to self for now

        // Before Balances
        uint256 balanceB4 = token.balanceOf(actor);
        uint256 balanceOfEscrowB4 = token.balanceOf(address(escrow));

        bool hasReverted;
        try centrifugeRouter.requestDeposit(address(vault), assets, actor, to, 0) {
            sumOfDepositRequests[address(token)] += assets;
            requestDepositAssets[actor][address(token)] += assets;
        } catch {
            hasReverted = true;
        }

        // After Balances and Checks
        uint256 balanceAfter = token.balanceOf(actor);
        uint256 balanceOfEscrowAfter = token.balanceOf(address(escrow));

        if (!hasReverted) {
            // Extra check
            unchecked {
                uint256 deltaUser = balanceB4 - balanceAfter;
                uint256 deltaEscrow = balanceOfEscrowAfter - balanceOfEscrowB4;

                if (RECON_EXACT_BAL_CHECK) {
                    eq(deltaUser, assets, "Extra LP-1");
                }

                eq(deltaUser, deltaEscrow, "LP-11");
            }
        }
    }

    function centrifugeRouter_cancelDepositRequest() public {
        // Before Balances
        uint256 balanceB4 = token.balanceOf(actor);
        uint256 balanceOfEscrowB4 = token.balanceOf(address(escrow));

        bool hasReverted;
        try centrifugeRouter.cancelDepositRequest(address(vault), 0) {
        } catch {
            hasReverted = true;
        }

        // After Balances and Checks
        uint256 balanceAfter = token.balanceOf(actor);
        uint256 balanceOfEscrowAfter = token.balanceOf(address(escrow));

        if (!hasReverted) {
            // Extra check
            unchecked {
                uint256 deltaUser = balanceAfter - balanceB4;
                uint256 deltaEscrow = balanceOfEscrowB4 - balanceOfEscrowAfter;

                eq(deltaUser, deltaEscrow, "LP-12");
            }
        }
    }

    // Helper function to get token balance for vault
    function _getTokenAndBalanceForVault() internal view returns (uint256) {
        return token.balanceOf(actor);
    }
}