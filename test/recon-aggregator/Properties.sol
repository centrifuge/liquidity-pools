// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.0;

import {Setup} from "./Setup.sol";
import {ArrayLib} from "src/libraries/ArrayLib.sol";

abstract contract Properties is Setup {
    using ArrayLib for uint16[8];

    function invariant_noMessageReplay() public view returns (bool) {
        for (uint256 i = 0; i < messages.length; i++) {
            bytes32 message = keccak256(messages[i]);
            if (messageReceivedCount[message] > messageSentCount[message] + messageRecoveredCount[message]) {
                return false;
            }

            // 1 > 0
            if (RECON_ADAPTERS > 1) {
                // Solo router -> Instant confirm
                // More than one, then we require 2 proofs > 1 message

                // 1 router => 1 received == 1 message sent, 0 proofs sent
                // 3 routers => 1 received == 1 message sent, 2 proofs sent
                if (
                    messageReceivedCount[message]
                        > (RECON_ADAPTERS - 1) * proofSentCount[message] + messageRecoveredCount[message]
                ) {
                    return false;
                }
            }
        }

        return true;
    }

    // When a message is executed, the total confirmation count is decreased by quorum
    function invariant_counter() public view returns (bool) {
        /// @audit CLAMP
        /// NOTE: When routers is 1, the property breaks
        if (RECON_ADAPTERS > 1) {
            for (uint256 i = 0; i < messages.length; i++) {
                bytes32 message = keccak256(messages[i]);

                if (routerAggregator.votes(message).countNonZeroValues() >= RECON_ADAPTERS) {
                    return false;
                }
            }
        }

        return true;
    }

    /// If sentCount == receivedCount -> Message must not be pending -> Message must have been cleared
    // function invariant_clear_pending_logic() public view returns (bool) {
    //     for (uint256 i = 0; i < messages.length; i++) {
    //         bytes32 message = keccak256(messages[i]);

    //         if (messageSentCount[message] + messageRecoveredCount[message] == messageReceivedCount[message]) {
    //             (, bytes memory pendingMessage) = routerAggregator.messages(message);
    //             if (pendingMessage.length != 0) {
    //                 return false; // Means it's not empty
    //             }
    //         }
    //     }

    //     return true;
    // }
}
