// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.26;

uint8 constant MAX_ADAPTER_COUNT = 8;

interface IGateway {
    /// @dev Each adapter struct is packed with the quorum to reduce SLOADs on handle
    struct Adapter {
        /// @notice Starts at 1 and maps to id - 1 as the index on the adapters array
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
        uint16[MAX_ADAPTER_COUNT] votes;
        /// @notice Each time adapters are updated, a new session starts which invalidates old votes
        uint64 sessionId;
        bytes pendingMessage;
    }

    struct Metadata {
        address source;
    }

    struct Transaction {
        address source;
        bytes message;
    }

    // --- Events ---
    event HandleMessage(bytes message, address adapter);
    event HandleProof(bytes32 messageHash, address adapter);
    event ExecuteMessage(bytes message, address adapter);
    event SendMessage(bytes message);
    event RecoverMessage(address adapter, bytes message);
    event RecoverProof(address adapter, bytes32 messageHash);
    event InitiateMessageRecovery(bytes32 messageHash, address adapter);
    event DisputeMessageRecovery(bytes32 messageHash, address adapter);
    event ExecuteMessageRecovery(bytes message, address adapter);
    event File(bytes32 indexed what, address[] adapters);
    event File(bytes32 indexed what, address instance);
    event File(bytes32 indexed what, uint8 messageId, address manager);
    event Received(address indexed sender, uint256 amount);

    // --- Administration ---
    /// @notice TODO
    function file(bytes32 what, address[] calldata adapters_) external;
    function file(bytes32 what, address data) external;
    function file(bytes32 what, uint8 data1, address data2) external;

    // --- Incoming ---
    /// @dev Handle incoming messages, proofs, and recoveries.
    ///      Assumes adapters ensure messages cannot be confirmed more than once.
    function handle(bytes calldata payload) external;

    /// @notice TODO
    function disputeMessageRecovery(address adapter, bytes32 messageHash) external;

    /// @dev Governance on Centrifuge Chain can initiate message recovery. After the challenge period,
    ///      the recovery can be executed. If a malign adapter initiates message recovery, governance on
    ///      Centrifuge Chain can dispute and immediately cancel the recovery, using any other valid adapter.
    ///
    ///      Only 1 recovery can be outstanding per message hash. If multiple adapters fail at the same time,
    //       these will need to be recovered serially (increasing the challenge period for each failed adapter).
    function executeMessageRecovery(address adapter, bytes calldata message) external;

    // --- Outgoing ---
    /// @dev Sends 1 message to the first adapter with the full message, and n-1 messages to the other adapters with
    ///      proofs (hash of message). This ensures message uniqueness (can only be executed on the destination once).
    function send(bytes calldata message, address source) external payable;

    /// @notice TODOGatewayTest
    function topUp() external payable;

    // --- Helpers ---
    /// @notice TODO
    function quorum() external view returns (uint8);

    /// @notice TODO
    function activeSessionId() external view returns (uint64);

    /// @notice TODO
    function votes(bytes32 messageHash) external view returns (uint16[MAX_ADAPTER_COUNT] memory votes);

    // @dev Used to calculate overall cost for bridging a payload on the first adapter and settling
    // on the destination chain and  bridging its payload proofs on n-1 adapter and settling on the destination chain.
    function estimate(bytes calldata payload) external view returns (uint256[] memory tranches, uint256 total);

    /// Used to recover any ERC-20 token.
    /// @dev - This method is called only by authorized entities
    /// @param token - the token address could be 0xeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee
    /// to recover locked native ETH or any ERC20 compatible token.
    /// @param to - address  that will receive the funds
    /// @param amount - amount to be sent to the @param to
    function recoverTokens(address token, address to, uint256 amount) external;
}

interface IMessageHandler {
    function handle(bytes memory message) external;
}
