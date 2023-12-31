// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import {MessagesLib} from "./../libraries/MessagesLib.sol";
import {BytesLib} from "src/libraries/BytesLib.sol";
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

interface RouterLike {
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
    PoolManagerLike public immutable poolManager;
    InvestmentManagerLike public immutable investmentManager;

    RouterLike public outgoingRouter;
    mapping(address => bool) public incomingRouters;

    mapping(uint8 => address) public managerByMessageId;

    // --- Events ---
    event File(bytes32 indexed what, address data);
    event File(bytes32 indexed what, address router, bool enabled);
    event File(bytes32 indexed what, uint8 messageId, address manager);

    constructor(address root_, address investmentManager_, address poolManager_, address router_) {
        root = RootLike(root_);
        investmentManager = InvestmentManagerLike(investmentManager_);
        poolManager = PoolManagerLike(poolManager_);
        incomingRouters[router_] = true;
        outgoingRouter = RouterLike(router_);

        wards[msg.sender] = 1;
        emit Rely(msg.sender);
    }

    modifier onlyIncomingRouter() {
        require(incomingRouters[msg.sender], "Gateway/only-router-allowed-to-call");
        _;
    }

    modifier pauseable() {
        require(!root.paused(), "Gateway/paused");
        _;
    }

    // --- Administration ---
    function file(bytes32 what, address router) public auth {
        if (what == "outgoingRouter") outgoingRouter = RouterLike(router);
        else revert("Gateway/file-unrecognized-param");
        emit File(what, router);
    }

    function file(bytes32 what, address router, bool enabled) public auth {
        if (what == "incomingRouter") incomingRouters[router] = enabled;
        else revert("Gateway/file-unrecognized-param");
        emit File(what, router, enabled);
    }

    function file(bytes32 what, uint8 messageId, address manager) public auth {
        if (what == "message") {
            require(messageId > 27, "Gateway/cannot-override-existing-message");
            managerByMessageId[messageId] = manager;
        } else {
            revert("Gateway/file-unrecognized-param");
        }
        emit File(what, messageId, manager);
    }

    // --- Outgoing ---
    function send(bytes calldata message) public pauseable {
        require(msg.sender == _getManager(message), "Gateway/invalid-manager");
        outgoingRouter.send(message);
    }

    // --- Incoming ---
    function handle(bytes calldata message) external onlyIncomingRouter pauseable {
        if (MessagesLib.isAddCurrency(message)) {
            (uint128 currency, address currencyAddress) = MessagesLib.parseAddCurrency(message);
            poolManager.addCurrency(currency, currencyAddress);
        } else if (MessagesLib.isAddPool(message)) {
            (uint64 poolId) = MessagesLib.parseAddPool(message);
            poolManager.addPool(poolId);
        } else if (MessagesLib.isAllowInvestmentCurrency(message)) {
            (uint64 poolId, uint128 currency) = MessagesLib.parseAllowInvestmentCurrency(message);
            poolManager.allowInvestmentCurrency(poolId, currency);
        } else if (MessagesLib.isAddTranche(message)) {
            (
                uint64 poolId,
                bytes16 trancheId,
                string memory tokenName,
                string memory tokenSymbol,
                uint8 decimals,
                uint8 restrictionSet
            ) = MessagesLib.parseAddTranche(message);
            poolManager.addTranche(poolId, trancheId, tokenName, tokenSymbol, decimals, restrictionSet);
        } else if (MessagesLib.isUpdateMember(message)) {
            (uint64 poolId, bytes16 trancheId, address user, uint64 validUntil) = MessagesLib.parseUpdateMember(message);
            poolManager.updateMember(poolId, trancheId, user, validUntil);
        } else if (MessagesLib.isUpdateTrancheTokenPrice(message)) {
            (uint64 poolId, bytes16 trancheId, uint128 currencyId, uint128 price, uint64 computedAt) =
                MessagesLib.parseUpdateTrancheTokenPrice(message);
            poolManager.updateTrancheTokenPrice(poolId, trancheId, currencyId, price, computedAt);
        } else if (MessagesLib.isTransfer(message)) {
            (uint128 currency, address recipient, uint128 amount) = MessagesLib.parseIncomingTransfer(message);
            poolManager.handleTransfer(currency, recipient, amount);
        } else if (MessagesLib.isTransferTrancheTokens(message)) {
            (uint64 poolId, bytes16 trancheId, address destinationAddress, uint128 amount) =
                MessagesLib.parseTransferTrancheTokens20(message);
            poolManager.handleTransferTrancheTokens(poolId, trancheId, destinationAddress, amount);
        } else if (MessagesLib.isExecutedDecreaseInvestOrder(message)) {
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
        } else if (MessagesLib.isExecutedDecreaseRedeemOrder(message)) {
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
        } else if (MessagesLib.isExecutedCollectInvest(message)) {
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
        } else if (MessagesLib.isExecutedCollectRedeem(message)) {
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
        } else if (MessagesLib.isScheduleUpgrade(message)) {
            address target = MessagesLib.parseScheduleUpgrade(message);
            root.scheduleRely(target);
        } else if (MessagesLib.isCancelUpgrade(message)) {
            address target = MessagesLib.parseCancelUpgrade(message);
            root.cancelRely(target);
        } else if (MessagesLib.isUpdateTrancheTokenMetadata(message)) {
            (uint64 poolId, bytes16 trancheId, string memory tokenName, string memory tokenSymbol) =
                MessagesLib.parseUpdateTrancheTokenMetadata(message);
            poolManager.updateTrancheTokenMetadata(poolId, trancheId, tokenName, tokenSymbol);
        } else if (MessagesLib.isTriggerIncreaseRedeemOrder(message)) {
            (uint64 poolId, bytes16 trancheId, address investor, uint128 currency, uint128 trancheTokenAmount) =
                MessagesLib.parseTriggerIncreaseRedeemOrder(message);
            investmentManager.handleTriggerIncreaseRedeemOrder(
                poolId, trancheId, investor, currency, trancheTokenAmount
            );
        } else if (MessagesLib.isFreeze(message)) {
            (uint64 poolId, bytes16 trancheId, address user) = MessagesLib.parseFreeze(message);
            poolManager.freeze(poolId, trancheId, user);
        } else if (MessagesLib.isUnfreeze(message)) {
            (uint64 poolId, bytes16 trancheId, address user) = MessagesLib.parseUnfreeze(message);
            poolManager.unfreeze(poolId, trancheId, user);
        } else if (MessagesLib.isDisallowInvestmentCurrency(message)) {
            (uint64 poolId, uint128 currency) = MessagesLib.parseDisallowInvestmentCurrency(message);
            poolManager.disallowInvestmentCurrency(poolId, currency);
        } else {
            revert("Gateway/invalid-message");
        }
    }

    // --- Helpers ---
    function _getManager(bytes calldata message) internal view returns (address) {
        uint8 id = BytesLib.toUint8(message, 0);

        // Hardcoded paths for pool & investment managers for gas efficiency
        if (id >= 1 && id <= 8) {
            return address(poolManager);
        } else if (id >= 9 && id <= 20) {
            return address(investmentManager);
        } else if (id >= 21 && id <= 26) {
            return address(poolManager);
        } else if (id == 27) {
            return address(investmentManager);
        } else {
            // Dynamic path for other managers, to be able to easily
            // extend functionality of Liquidity Pools
            address manager = managerByMessageId[id];
            require(manager != address(0), "Gateway/unregistered-message-id");
            return manager;
        }
    }

    function _addressToBytes32(address x) internal pure returns (bytes32) {
        return bytes32(bytes20(x));
    }
}
