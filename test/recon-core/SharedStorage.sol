// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.26;

import {ERC20} from "src/token/ERC20.sol";

abstract contract SharedStorage {
    /**
     * GLOBAL SETTINGS
     */
    uint8 constant RECON_MODULO_DECIMALS = 19; // NOTE: Caps to 18

    // Reenable canary tests, to help determine if coverage goals are being met
    bool constant RECON_TOGGLE_CANARY_TESTS = false;

    // Properties we did not implement and we do not want that to be flagged
    bool RECON_SKIPPED_PROPERTY = true;

    // NOTE: This is to not clog up the logs
    bool TODO_RECON_SKIP_ERC7540 = false;

    // Prevent flagging of properties that have been acknowledged
    bool TODO_RECON_SKIP_ACKNOWLEDGED_CASES = true;

    // Disable them by setting this to false
    bool RECON_USE_SENTINEL_TESTS = false;

    // Gateway Mock
    bool RECON_USE_HARDCODED_DECIMALS = false; // Should we use random or hardcoded decimals?
    bool RECON_USE_SINGLE_DEPLOY = true; // NOTE: Actor Properties break if you use multi cause they are
        // mono-dimensional

    // Should we also enforce the exact balance check on asset / shares?
    // TODO: This is broken rn
    // Liquidity Pool functions
    bool RECON_EXACT_BAL_CHECK = true;

    /// === INTERNAL COUNTERS === ///
    // Currency ID = Currency Length
    // Pool ID = Pool Length
    // Tranche ID = Tranche Length . toId
    uint64 CURRENCY_ID = 1;
    uint64 POOL_ID = 1;
    uint16 TRANCHE_COUNTER = 1;
    // Hash of index + salt, but we use number to be able to cycle
    bytes16 TRANCHE_ID = bytes16(bytes32(uint256(TRANCHE_COUNTER)));

    // NOTE: TODO
    // ** INCOMPLETE - Deployment, Setup and Cycling of Assets, Tranches, Pools and Vaults **/
    // Step 1
    // Make Currency
    ERC20[] allTokens;
    /// TODO: Consider dropping
    mapping(address => uint128) tokenToCurrencyId;
    mapping(uint128 => address) currencyIdToToken;

    // TODO: Consider refactoring to a address of Currency or Tranche to get the rest of the details
    address[] trancheTokens; // TODO: Tranche to ID
    address[] vaults; // TODO: Liquidity To ID?

    // === invariant_E_1 === //
    // Currency
    // Indexed by Currency
    /**
     * See:
     *         - vault_requestDeposit
     */
    mapping(address => uint256) sumOfDepositRequests;
    /**
     * See:
     *         - invariant_erc7540_9_r
     *         - invariant_erc7540_9_w
     *         - vault_redeem
     *         - vault_withdraw
     */
    mapping(address => uint256) sumOfClaimedRedemptions;

    /**
     * See:
     *         - poolManager_handleTransfer(bytes32 recipient, uint128 amount)
     *         - poolManager_handleTransfer(address recipient, uint128 amount)
     *
     *         - poolManager_transfer
     */
    mapping(address => uint256) sumOfTransfersIn;

    /**
     * See:
     *     -   poolManager_handleTransfer
     */
    mapping(address => uint256) sumOfTransfersOut;

    // Global-1
    mapping(address => uint256) cancelRedeemTrancheTokenPayout;
    // Global-2
    mapping(address => uint256) cancelDepositCurrencyPayout;

    // END === invariant_E_1 === //

    // UNSURE | TODO
    // Pretty sure I need to clamp by an amount sent by the user
    // Else they get like a bazillion tokens
    mapping(address => bool) hasRequestedDepositCancellation;
    mapping(address => bool) hasRequestedRedeemCancellation;

    // === invariant_E_2 === //
    // Tranche
    // Indexed by Tranche Token

    /**
     * // TODO: Jeroen to review!
     *     // NOTE This is basically an imaginary counter
     *     // It's not supposed to work this way in reality
     *     // TODO: MUST REMOVE
     *     See:
     *         - investmentManager_fulfillCancelRedeemRequest
     *         - investmentManager_fulfillRedeemRequest // NOTE: Used by E_1
     */
    mapping(address => uint256) mintedByCurrencyPayout;
    /**
     * See:
     *         - investmentManager_fulfillDepositRequest
     */
    mapping(address => uint256) sumOfFullfilledDeposits;

    /**
     * See:
     *         -
     */
    mapping(address => uint256) sumOfClaimedDeposits;

    /**
     * See:
     *         - vault_requestRedeem
     *         - investmentManager_triggerRedeemRequest
     */
    mapping(address => uint256) sumOfRedeemRequests;

    /**
     * See:
     *         - investmentManager_fulfillRedeemRequest
     */
    mapping(address => uint256) sumOfClaimedRequests;

    mapping(address => uint256) sumOfClaimedDepositCancelations;
    mapping(address => uint256) sumOfClaimedRedeemCancelations;

    // END === invariant_E_2 === //

    // NOTE: OLD
    mapping(address => uint256) totalCurrenciesSent;
    mapping(address => uint256) totalTrancheSent;

    // These are used by invariant_global_3
    mapping(address => uint256) executedInvestments;
    mapping(address => uint256) executedRedemptions;

    mapping(address => uint256) incomingTransfers;
    mapping(address => uint256) outGoingTransfers;

    // NOTE: You need to decide if these should exist
    mapping(address => uint256) trancheMints;

    // TODO: Global-1 and Global-2
    // Something is off
    /**
     * handleExecutedCollectInvest
     *     handleExecutedCollectRedeem
     */

    // Global-1
    mapping(address => uint256) claimedAmounts;

    // Global-2
    mapping(address => uint256) depositRequests;

    // Requests
    // NOTE: We need to store request data to be able to cap the values as otherwise the
    // System will enter an inconsistent state
    mapping(address => mapping(address => uint256)) requestDepositAssets;
    mapping(address => mapping(address => uint256)) requestRedeemShares;

    // === invariant_RE_1 === //
    // Indexed by Currency
    mapping(address => uint256) sumOfLockedDepositRequests;
    mapping(address => uint256) sumOfUnlockedDepositRequests;
    mapping(address => uint256) sumOfExecutedLockedDepositRequests;
    // stores request data coming through the router
    mapping(address => uint256) sumOfDepositRequestsRouter;
}
