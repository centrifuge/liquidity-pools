// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import {BytesLib} from "src/libraries/BytesLib.sol";
import {CastLib} from "src/libraries/CastLib.sol";

/// @title  MessagesLib
/// @dev    Library for encoding and decoding messages.
library MessagesLib {
    using BytesLib for bytes;
    using CastLib for *;

    enum Call {
        /// 0 - An invalid message
        Invalid,
        // --- Gateway ---
        /// 1 - Proof
        MessageProof,
        /// 2 - Initiate Message Recovery
        InitiateMessageRecovery,
        /// 3 - Dispute Message Recovery
        DisputeMessageRecovery,
        /// 4 - Batch Messages
        Batch,
        // --- Root ---
        /// 5 - Schedule an upgrade contract to be granted admin rights
        ScheduleUpgrade,
        /// 6 - Cancel a previously scheduled upgrade
        CancelUpgrade,
        /// 7 - Recover tokens sent to the wrong contract
        RecoverTokens,
        // --- Gas service ---
        /// 8 - Update Centrifuge Gas Price
        UpdateCentrifugeGasPrice,
        // --- Pool Manager ---
        /// 9 - Add an asset id -> EVM address mapping
        AddAsset,
        /// 10 - Add Pool
        AddPool,
        /// 11 - Add a Pool's Tranche Token
        AddTranche,
        /// 12 - Allow an asset to be used as an asset for investing in pools
        AllowAsset,
        /// 13 - Disallow an asset to be used as an asset for investing in pools
        DisallowAsset,
        /// 14 - Update the price of a Tranche Token
        UpdateTranchePrice,
        /// 15 - Update tranche token metadata
        UpdateTrancheMetadata,
        /// 16 - A transfer of assets
        TransferAssets,
        /// 17 - A transfer of tranche tokens
        TransferTrancheTokens,
        /// 18 - Update a user restriction
        UpdateRestriction,
        /// --- Investment Manager ---
        /// 21 - Increase an investment order by a given amount
        DepositRequest,
        /// 22 - Increase a Redeem order by a given amount
        RedeemRequest,
        /// 23 - Executed Collect Invest
        FulfilledDepositRequest,
        /// 24 - Executed Collect Redeem
        FulfilledRedeemRequest,
        /// 25 - Cancel an investment order
        CancelDepositRequest,
        /// 26 - Cancel a redeem order
        CancelRedeemRequest,
        /// 27 - Executed Decrease Invest Order
        FulfilledCancelDepositRequest,
        /// 28 - Executed Decrease Redeem Order
        FulfilledCancelRedeemRequest,
        /// 29 - Request redeem investor
        TriggerRedeemRequest
    }

    enum Domain {
        Centrifuge,
        EVM
    }

    function messageType(bytes memory _msg) internal pure returns (Call _call) {
        _call = Call(_msg.toUint8(0));
    }

    // Utils
    function formatDomain(Domain domain) internal pure returns (bytes9) {
        return bytes9(bytes1(uint8(domain)));
    }

    function formatDomain(Domain domain, uint64 chainId) internal pure returns (bytes9) {
        return bytes9(BytesLib.slice(abi.encodePacked(uint8(domain), chainId), 0, 9));
    }
}
