// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import {MessagesLib} from "./../libraries/MessagesLib.sol";
import {Auth} from "./../Auth.sol";

interface InvestmentManagerLike {
    function handleExecutedDecreaseInvestOrder(
        uint64 poolId,
        bytes16 trancheId,
        address investor,
        uint128 currency,
        uint128 currencyPayout,
        uint128 remainingInvestOrder
    ) external;
    function handleExecutedDecreaseRedeemOrder(
        uint64 poolId,
        bytes16 trancheId,
        address investor,
        uint128 currency,
        uint128 trancheTokensPayout,
        uint128 remainingRedeemOrder
    ) external;
    function handleExecutedCollectInvest(
        uint64 poolId,
        bytes16 trancheId,
        address investor,
        uint128 currency,
        uint128 currencyPayout,
        uint128 trancheTokensPayout,
        uint128 remainingInvestOrder
    ) external;
    function handleExecutedCollectRedeem(
        uint64 poolId,
        bytes16 trancheId,
        address investor,
        uint128 currency,
        uint128 currencyPayout,
        uint128 trancheTokensPayout,
        uint128 remainingRedeemOrder
    ) external;
    function handleTriggerIncreaseRedeemOrder(
        uint64 poolId,
        bytes16 trancheId,
        address investor,
        uint128 currency,
        uint128 trancheTokenAmount
    ) external;
}

interface PoolManagerLike {
    function addPool(uint64 poolId) external;
    function allowInvestmentCurrency(uint64 poolId, uint128 currency) external;
    function disallowInvestmentCurrency(uint64 poolId, uint128 currency) external;
    function addTranche(
        uint64 poolId,
        bytes16 trancheId,
        string memory tokenName,
        string memory tokenSymbol,
        uint8 decimals,
        uint8 restrictionSet
    ) external;
    function updateMember(uint64 poolId, bytes16 trancheId, address user, uint64 validUntil) external;
    function freeze(uint64 poolId, bytes16 trancheId, address user) external;
    function unfreeze(uint64 poolId, bytes16 trancheId, address user) external;
    function updateTrancheTokenMetadata(
        uint64 poolId,
        bytes16 trancheId,
        string memory tokenName,
        string memory tokenSymbol
    ) external;
    function updateTrancheTokenPrice(
        uint64 poolId,
        bytes16 trancheId,
        uint128 currencyId,
        uint128 price,
        uint64 computedAt
    ) external;
    function addCurrency(uint128 currency, address currencyAddress) external;
    function handleTransfer(uint128 currency, address recipient, uint128 amount) external;
    function handleTransferTrancheTokens(uint64 poolId, bytes16 trancheId, address destinationAddress, uint128 amount)
        external;
}

interface RouterAggregatorLike {
    function send(bytes memory message) external;
}

interface RootLike {
    function paused() external returns (bool);
    function scheduleRely(address target) external;
    function cancelRely(address target) external;
}

/// @title  Gateway
/// @dev    It parses incoming messages and forwards these to Managers
///         and it encoded outgoing messages and sends these to Routers.
///
///         If the Root is paused, any messages in and out of this contract
///         will not be forwarded
contract Gateway is Auth {
    RootLike public immutable root;
    PoolManagerLike public poolManager;
    InvestmentManagerLike public investmentManager;

    RouterAggregatorLike public aggregator;

    // --- Events ---
    event File(bytes32 indexed what, address data);
    event AddIncomingRouter(address indexed router);
    event RemoveIncomingRouter(address indexed router);
    event UpdateOutgoingRouter(address indexed router);

    constructor(address root_, address investmentManager_, address poolManager_) {
        root = RootLike(root_);
        investmentManager = InvestmentManagerLike(investmentManager_);
        poolManager = PoolManagerLike(poolManager_);

        wards[msg.sender] = 1;
        emit Rely(msg.sender);
    }

    modifier pauseable() {
        require(!root.paused(), "Gateway/paused");
        _;
    }

    // --- Administration ---
    function file(bytes32 what, address data) public auth {
        if (what == "poolManager") poolManager = PoolManagerLike(data);
        else if (what == "aggregator") aggregator = RouterAggregatorLike(data);
        else if (what == "investmentManager") investmentManager = InvestmentManagerLike(data);
        else revert("Gateway/file-unrecognized-param");
        emit File(what, data);
    }

    // --- Outgoing ---
    function send(bytes calldata message) public pauseable {
        // TODO: check by message ID, that the origin matches
        require(
            msg.sender == address(investmentManager) || msg.sender == address(poolManager), "Gateway/invalid-manager"
        );
        aggregator.send(message);
    }

    // --- Incoming ---
    function handle(bytes calldata message) external auth pauseable {
        MessagesLib.Call call = MessagesLib.messageType(message);

        if (call == MessagesLib.Call.AddCurrency) {
            (uint128 currency, address currencyAddress) = MessagesLib.parseAddCurrency(message);
            poolManager.addCurrency(currency, currencyAddress);
        } else if (call == MessagesLib.Call.AddPool) {
            (uint64 poolId) = MessagesLib.parseAddPool(message);
            poolManager.addPool(poolId);
        } else if (call == MessagesLib.Call.AllowInvestmentCurrency) {
            (uint64 poolId, uint128 currency) = MessagesLib.parseAllowInvestmentCurrency(message);
            poolManager.allowInvestmentCurrency(poolId, currency);
        } else if (call == MessagesLib.Call.AddTranche) {
            (
                uint64 poolId,
                bytes16 trancheId,
                string memory tokenName,
                string memory tokenSymbol,
                uint8 decimals,
                uint8 restrictionSet
            ) = MessagesLib.parseAddTranche(message);
            poolManager.addTranche(poolId, trancheId, tokenName, tokenSymbol, decimals, restrictionSet);
        } else if (call == MessagesLib.Call.UpdateMember) {
            (uint64 poolId, bytes16 trancheId, address user, uint64 validUntil) = MessagesLib.parseUpdateMember(message);
            poolManager.updateMember(poolId, trancheId, user, validUntil);
        } else if (call == MessagesLib.Call.UpdateTrancheTokenPrice) {
            (uint64 poolId, bytes16 trancheId, uint128 currencyId, uint128 price, uint64 computedAt) =
                MessagesLib.parseUpdateTrancheTokenPrice(message);
            poolManager.updateTrancheTokenPrice(poolId, trancheId, currencyId, price, computedAt);
        } else if (call == MessagesLib.Call.Transfer) {
            (uint128 currency, address recipient, uint128 amount) = MessagesLib.parseIncomingTransfer(message);
            poolManager.handleTransfer(currency, recipient, amount);
        } else if (call == MessagesLib.Call.TransferTrancheTokens) {
            (uint64 poolId, bytes16 trancheId, address destinationAddress, uint128 amount) =
                MessagesLib.parseTransferTrancheTokens20(message);
            poolManager.handleTransferTrancheTokens(poolId, trancheId, destinationAddress, amount);
        } else if (call == MessagesLib.Call.ExecutedDecreaseInvestOrder) {
            (
                uint64 poolId,
                bytes16 trancheId,
                address investor,
                uint128 currency,
                uint128 currencyPayout,
                uint128 remainingInvestOrder
            ) = MessagesLib.parseExecutedDecreaseInvestOrder(message);
            investmentManager.handleExecutedDecreaseInvestOrder(
                poolId, trancheId, investor, currency, currencyPayout, remainingInvestOrder
            );
        } else if (call == MessagesLib.Call.ExecutedDecreaseRedeemOrder) {
            (
                uint64 poolId,
                bytes16 trancheId,
                address investor,
                uint128 currency,
                uint128 trancheTokensPayout,
                uint128 remainingRedeemOrder
            ) = MessagesLib.parseExecutedDecreaseRedeemOrder(message);
            investmentManager.handleExecutedDecreaseRedeemOrder(
                poolId, trancheId, investor, currency, trancheTokensPayout, remainingRedeemOrder
            );
        } else if (call == MessagesLib.Call.ExecutedCollectInvest) {
            (
                uint64 poolId,
                bytes16 trancheId,
                address investor,
                uint128 currency,
                uint128 currencyPayout,
                uint128 trancheTokensPayout,
                uint128 remainingInvestOrder
            ) = MessagesLib.parseExecutedCollectInvest(message);
            investmentManager.handleExecutedCollectInvest(
                poolId, trancheId, investor, currency, currencyPayout, trancheTokensPayout, remainingInvestOrder
            );
        } else if (call == MessagesLib.Call.ExecutedCollectRedeem) {
            (
                uint64 poolId,
                bytes16 trancheId,
                address investor,
                uint128 currency,
                uint128 currencyPayout,
                uint128 trancheTokensPayout,
                uint128 remainingRedeemOrder
            ) = MessagesLib.parseExecutedCollectRedeem(message);
            investmentManager.handleExecutedCollectRedeem(
                poolId, trancheId, investor, currency, currencyPayout, trancheTokensPayout, remainingRedeemOrder
            );
        } else if (call == MessagesLib.Call.ScheduleUpgrade) {
            address target = MessagesLib.parseScheduleUpgrade(message);
            root.scheduleRely(target);
        } else if (call == MessagesLib.Call.CancelUpgrade) {
            address target = MessagesLib.parseCancelUpgrade(message);
            root.cancelRely(target);
        } else if (call == MessagesLib.Call.UpdateTrancheTokenMetadata) {
            (uint64 poolId, bytes16 trancheId, string memory tokenName, string memory tokenSymbol) =
                MessagesLib.parseUpdateTrancheTokenMetadata(message);
            poolManager.updateTrancheTokenMetadata(poolId, trancheId, tokenName, tokenSymbol);
        } else if (call == MessagesLib.Call.TriggerIncreaseRedeemOrder) {
            (uint64 poolId, bytes16 trancheId, address investor, uint128 currency, uint128 trancheTokenAmount) =
                MessagesLib.parseTriggerIncreaseRedeemOrder(message);
            investmentManager.handleTriggerIncreaseRedeemOrder(
                poolId, trancheId, investor, currency, trancheTokenAmount
            );
        } else if (call == MessagesLib.Call.Freeze) {
            (uint64 poolId, bytes16 trancheId, address user) = MessagesLib.parseFreeze(message);
            poolManager.freeze(poolId, trancheId, user);
        } else if (call == MessagesLib.Call.Unfreeze) {
            (uint64 poolId, bytes16 trancheId, address user) = MessagesLib.parseUnfreeze(message);
            poolManager.unfreeze(poolId, trancheId, user);
        } else if (call == MessagesLib.Call.DisallowInvestmentCurrency) {
            (uint64 poolId, uint128 currency) = MessagesLib.parseDisallowInvestmentCurrency(message);
            poolManager.disallowInvestmentCurrency(poolId, currency);
        } else {
            revert("Gateway/invalid-message");
        }
    }
}
