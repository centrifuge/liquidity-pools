// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import {IGateway} from "src/interfaces/gateway/IGateway.sol";
import {IAggregator} from "src/interfaces/gateway/IAggregator.sol";

uint8 constant MAX_ROUTER_COUNT = 8;

interface IGatewayV2 {
    /// @dev Each router struct is packed with the quorum to reduce SLOADs on handle
    struct Router {
        /// @notice Starts at 1 and maps to id - 1 as the index on the routers array
        uint8 id;
        /// @notice Number of votes required for a message to be executed
        uint8 quorum;
        /// @notice Each time the quorum is decreased, a new session starts which invalidates old votes
        uint64 activeSessionId;
    }

    struct Message {
        /// @dev Counts are stored as integers (instead of boolean values) to accommodate duplicate
        ///      messages (e.g. two investments from the same user with the same amount) being
        ///      processed in parallel. The entire struct is packed in a single bytes32 slot.
        ///      Max uint16 = 65,535 so at most 65,535 duplicate messages can be processed in parallel.
        uint16[MAX_ROUTER_COUNT] votes;
        /// @notice Each time routers are updated, a new session starts which invalidates old votes
        uint64 sessionId;
        bytes pendingMessage;
    }

    struct Recovery {
        uint256 timestamp;
        address router;
    }

    // --- Events ---
    event HandleMessage(bytes message, address router);
    event HandleProof(bytes32 messageHash, address router);
    event ExecuteMessage(bytes message, address router);
    event SendMessage(bytes message);
    event RecoverMessage(address router, bytes message);
    event RecoverProof(address router, bytes32 messageHash);
    event InitiateMessageRecovery(bytes32 messageHash, address router);
    event DisputeMessageRecovery(bytes32 messageHash);
    event ExecuteMessageRecovery(bytes message);
    event File(bytes32 indexed what, address[] routers);
    event File(bytes32 indexed what, address instance);
    event File(bytes32 indexed what, uint8 messageId, address manager);
    event Received(address indexed sender, uint256 amount);

    // --- Administration ---
    /// @notice TODO
    function file(bytes32 what, address[] calldata routers_) external;
    function file(bytes32 what, address data) external;
    function file(bytes32 what, uint8 data1, address data2) external;

    // --- Incoming ---
    /// @dev Handle incoming messages, proofs, and recoveries.
    ///      Assumes routers ensure messages cannot be confirmed more than once.
    function handle(bytes calldata payload) external;

    /// @notice TODO
    function disputeMessageRecovery(bytes32 messageHash) external;

    /// @dev Governance on Centrifuge Chain can initiate message recovery. After the challenge period,
    ///      the recovery can be executed. If a malign router initiates message recovery, governance on
    ///      Centrifuge Chain can dispute and immediately cancel the recovery, using any other valid router.
    ///
    ///      Only 1 recovery can be outstanding per message hash. If multiple routers fail at the same time,
    //       these will need to be recovered serially (increasing the challenge period for each failed router).
    function executeMessageRecovery(bytes calldata message) external;

    // --- Outgoing ---
    /// @dev Sends 1 message to the first router with the full message, and n-1 messages to the other routers with
    ///      proofs (hash of message). This ensures message uniqueness (can only be executed on the destination once).
    function send(bytes calldata message) external payable;

    // --- Helpers ---
    /// @notice TODO
    function quorum() external view returns (uint8);

    /// @notice TODO
    function activeSessionId() external view returns (uint64);

    /// @notice TODO
    function votes(bytes32 messageHash) external view returns (uint16[MAX_ROUTER_COUNT] memory votes);

    // @dev Used to calculate overall cost for bridging a payload on the first router and settling
    // on the destination chain and  bridging its payload proofs on n-1 router and settling on the destination chain.
    function estimate(bytes calldata payload) external view returns (uint256[] memory tranches, uint256 total);

    /// Used to recover any ERC-20 token.
    /// @dev - This method is called only by authorized entities
    /// @param token - the token address could be 0xeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee
    /// to recover locked native ETH or any ERC20 compatible token.
    /// @param to - address  that will receive the funds
    /// @param amount - amount to be sent to the @param to
    function recoverTokens(address token, address to, uint256 amount) external;
}
