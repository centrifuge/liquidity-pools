// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import {Auth} from "src/Auth.sol";
import {ArrayLib} from "src/libraries/ArrayLib.sol";
import {BytesLib} from "src/libraries/BytesLib.sol";
import {MessagesLib} from "src/libraries/MessagesLib.sol";
import {IAggregator} from "src/interfaces/gateway/IAggregator.sol";

interface GatewayLike {
    function handle(bytes memory message) external;
}

interface GasServiceLike {
    function estimate(bytes calldata payload) external view returns (uint256);
}

interface RouterLike {
    function send(bytes memory message) external;
    function pay(bytes calldata payload, address refund) external payable;
    function estimate(bytes calldata payload, uint256 destChainCost) external view returns (uint256);
}

/// @title  Aggregator
/// @notice Routing contract that forwards to multiple routers (1 full message, n-1 proofs)
///         and validates multiple routers have confirmed a message.
///
///         Supports processing multiple duplicate messages in parallel by
///         storing counts of messages and proofs that have been received.
contract Aggregator is Auth, IAggregator {
    using ArrayLib for uint16[8];
    using BytesLib for bytes;

    uint8 public constant MAX_ROUTER_COUNT = 8;
    uint8 public constant PRIMARY_ROUTER_ID = 1;
    uint256 public constant RECOVERY_CHALLENGE_PERIOD = 7 days;

    GatewayLike public immutable gateway;
    GasServiceLike public gasService;

    address[] public routers;
    mapping(address router => Router) public activeRouters;
    mapping(bytes32 messageHash => Message) public messages;
    mapping(address router => mapping(bytes32 messageHash => uint256 timestamp)) public recoveries;

    constructor(address gateway_, address gasService_) {
        gateway = GatewayLike(gateway_);
        gasService = GasServiceLike(gasService_);

        wards[msg.sender] = 1;
        emit Rely(msg.sender);
    }

    // --- Administration ---
    /// @inheritdoc IAggregator
    function file(bytes32 what, address[] calldata routers_) external auth {
        if (what == "routers") {
            uint8 quorum_ = uint8(routers_.length);
            require(quorum_ > 0, "Aggregator/empty-router-set");
            require(quorum_ <= MAX_ROUTER_COUNT, "Aggregator/exceeds-max-router-count");

            uint64 sessionId = 0;
            if (routers.length > 0) {
                // Increment session id if it is not the initial router setup and the quorum was decreased
                Router memory prevRouter = activeRouters[routers[0]];
                sessionId = quorum_ < prevRouter.quorum ? prevRouter.activeSessionId + 1 : prevRouter.activeSessionId;
            }

            // Disable old routers
            for (uint8 i = 0; i < routers.length; i++) {
                delete activeRouters[routers[i]];
            }

            // Enable new routers, setting quorum to number of routers
            for (uint8 j; j < quorum_; j++) {
                require(activeRouters[routers_[j]].id == 0, "Aggregator/no-duplicates-allowed");

                // Ids are assigned sequentially starting at 1
                activeRouters[routers_[j]] = Router(j + 1, quorum_, sessionId);
            }

            routers = routers_;
        } else {
            revert("Aggregator/file-unrecognized-param");
        }

        emit File(what, routers_);
    }

    function file(bytes32 what, address instance) external auth {
        if (what == "gasService") gasService = GasServiceLike(instance);
        else revert("Aggregator/file-unrecognized-param");

        emit File(what, instance);
    }

    // --- Incoming ---
    /// @inheritdoc IAggregator
    function handle(bytes calldata payload) external {
        _handle(payload, msg.sender, false);
    }

    function _handle(bytes calldata payload, address router_, bool isRecovery) internal {
        Router memory router = activeRouters[router_];
        require(router.id != 0, "Aggregator/invalid-router");

        MessagesLib.Call call = MessagesLib.messageType(payload);
        if (call == MessagesLib.Call.InitiateMessageRecovery || call == MessagesLib.Call.DisputeMessageRecovery) {
            require(!isRecovery, "Aggregator/no-recursive-recovery-allowed");
            require(routers.length > 1, "Aggregator/no-recovery-with-one-router-allowed");
            return _handleRecovery(payload);
        }

        bool isMessageProof = call == MessagesLib.Call.MessageProof;
        if (router.quorum == 1 && !isMessageProof) {
            // Special case for gas efficiency
            gateway.handle(payload);
            emit ExecuteMessage(payload, router_);
            return;
        }

        // Verify router and parse message hash
        bytes32 messageHash;
        if (isMessageProof) {
            require(isRecovery || router.id != PRIMARY_ROUTER_ID, "RouterAggregator/non-proof-router");
            messageHash = payload.toBytes32(1);
            emit HandleProof(messageHash, router_);
        } else {
            require(isRecovery || router.id == PRIMARY_ROUTER_ID, "RouterAggregator/non-message-router");
            messageHash = keccak256(payload);
            emit HandleMessage(payload, router_);
        }

        Message storage state = messages[messageHash];

        if (router.activeSessionId != state.sessionId) {
            // Clear votes from previous session
            delete state.votes;
            state.sessionId = router.activeSessionId;
        }

        // Increase vote
        state.votes[router.id - 1]++;

        if (state.votes.countNonZeroValues() >= router.quorum) {
            // Reduce votes by quorum
            state.votes.decreaseFirstNValues(router.quorum);

            // Handle message
            if (isMessageProof) {
                gateway.handle(state.pendingMessage);
            } else {
                gateway.handle(payload);
            }

            // Only if there are no more pending messages, remove the pending message
            if (state.votes.isEmpty()) {
                delete state.pendingMessage;
            }

            emit ExecuteMessage(payload, msg.sender);
        } else if (!isMessageProof) {
            state.pendingMessage = payload;
        }
    }

    function _handleRecovery(bytes memory payload) internal {
        if (MessagesLib.messageType(payload) == MessagesLib.Call.InitiateMessageRecovery) {
            bytes32 messageHash = payload.toBytes32(1);
            address router = payload.toAddress(33);
            require(activeRouters[msg.sender].id != 0, "Aggregator/invalid-sender");
            require(activeRouters[router].id != 0, "Aggregator/invalid-router");
            recoveries[router][messageHash] = block.timestamp + RECOVERY_CHALLENGE_PERIOD;
            emit InitiateMessageRecovery(messageHash, router);
        } else if (MessagesLib.messageType(payload) == MessagesLib.Call.DisputeMessageRecovery) {
            bytes32 messageHash = payload.toBytes32(1);
            address router = payload.toAddress(33);
            return _disputeMessageRecovery(router, messageHash);
        }
    }

    /// @inheritdoc IAggregator
    function disputeMessageRecovery(address router, bytes32 messageHash) external auth {
        _disputeMessageRecovery(router, messageHash);
    }

    function _disputeMessageRecovery(address router, bytes32 messageHash) internal {
        delete recoveries[router][messageHash];
        emit DisputeMessageRecovery(messageHash, router);
    }

    /// @inheritdoc IAggregator
    function executeMessageRecovery(address router_, bytes calldata message) external {
        bytes32 messageHash = keccak256(message);
        uint256 recovery = recoveries[router_][messageHash];

        require(recovery != 0, "Aggregator/message-recovery-not-initiated");
        require(recovery <= block.timestamp, "Aggregator/challenge-period-has-not-ended");

        delete recoveries[router_][messageHash];
        _handle(message, router_, true);
        emit ExecuteMessageRecovery(message, router_);
    }

    // --- Outgoing ---
    /// @inheritdoc IAggregator
    function send(bytes calldata message) external payable auth {
        uint256 numRouters = routers.length;
        require(numRouters > 0, "Aggregator/not-initialized");

        uint256 fuel = msg.value;

        uint256 destChainMsgCost;
        uint256 destChainProofCost;

        bytes memory proof = abi.encodePacked(uint8(MessagesLib.Call.MessageProof), keccak256(message));

        if (fuel > 0) {
            destChainMsgCost = gasService.estimate(message);
            destChainProofCost = gasService.estimate(proof);
        }

        for (uint256 i; i < numRouters; i++) {
            RouterLike currentRouter = RouterLike(routers[i]);
            bytes memory payload = i == PRIMARY_ROUTER_ID - 1 ? message : proof;
            // TODO a discussion:
            // Assumption 1: We would like to be able to call `send` without providing any funds for gas payments
            // Assumption 2: Funds for gas payments might be provided by EOA  but the estimated value could be retrieved
            // on a previous block.
            // Assumption 3: There is volatility and fluctuation in axelar Cost and centrifuge Cost
            //
            // Resolution 1: If no one is paying for the gas funds, there is no point in providing an array of
            // gas costs for each router from the outside
            // Resolution 2: During the TX runtime, we get latest updated value in all our contract for all the fee
            // and make calculation based on that. If the provide value "fuel" turns out to be not enough, we receive
            // a faster feedback and we don't have to submit the tx on axelar or any other bridge and wait for a
            // feedback that the tx will end up being underpaid
            // Resolution 3: Resolution 2 applies - we get the latest updated costs on centra and axelar assuming they
            // got updated

            if (fuel > 0) {
                uint256 txCost =
                    currentRouter.estimate(payload, i == PRIMARY_ROUTER_ID - 1 ? destChainMsgCost : destChainProofCost);
                uint256 remaining;
                unchecked {
                    remaining = fuel - txCost;
                }
                require(remaining < fuel, "Aggregator/not-enough-gas-funds");
                fuel = remaining;
                currentRouter.pay{value: txCost}(payload, address(gateway));
            }

            currentRouter.send(payload);
        }

        if (fuel > 0) payable(address(gateway)).transfer(fuel);

        emit SendMessage(message);
    }

    // --- Helpers ---
    /// @inheritdoc IAggregator
    function quorum() external view returns (uint8) {
        Router memory router = activeRouters[routers[0]];
        return router.quorum;
    }

    /// @inheritdoc IAggregator
    function activeSessionId() external view returns (uint64) {
        Router memory router = activeRouters[routers[0]];
        return router.activeSessionId;
    }

    /// @inheritdoc IAggregator
    function votes(bytes32 messageHash) external view returns (uint16[8] memory) {
        return messages[messageHash].votes;
    }

    /// @inheritdoc IAggregator
    function estimate(bytes calldata payload) external view returns (uint256 estimated) {
        bytes memory proof = abi.encodePacked(uint8(MessagesLib.Call.MessageProof), keccak256(payload));
        uint256 destChainCost = gasService.estimate(payload);

        for (uint256 i; i < routers.length; i++) {
            estimated += RouterLike(routers[i]).estimate(i == PRIMARY_ROUTER_ID - 1 ? payload : proof, destChainCost);
        }
    }
}
