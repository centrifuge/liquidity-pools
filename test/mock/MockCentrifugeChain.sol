// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import {Messages} from "src/gateway/Messages.sol";
import "forge-std/Test.sol";
import {XCMRouter} from "src/gateway/routers/xcm/Router.sol";

interface RouterLike {
    function execute(bytes memory _message) external;
}

contract MockCentrifugeChain is Test {
    RouterLike public immutable router;

    uint32 public dispatchDomain;
    uint256 public dispatchChainId;
    bytes public dispatchMessage;
    bytes32 public dispatchRecipient;
    uint256 public dispatchCalls;

    enum Types {AddPool}

    constructor(address xcmRouter) {
        router = RouterLike(xcmRouter);
    }

    function addCurrency(uint128 currency, address currencyAddress) public {
        bytes memory _message = Messages.formatAddCurrency(currency, currencyAddress);
        router.execute(_message);
    }

    function addPool(uint64 poolId) public {
        bytes memory _message = Messages.formatAddPool(poolId);
        router.execute(_message);
    }

    function allowInvestmentCurrency(uint64 poolId, uint128 currency) public {
        bytes memory _message = Messages.formatAllowInvestmentCurrency(poolId, currency);
        router.execute(_message);
    }

    function disallowInvestmentCurrency(uint64 poolId, uint128 currency) public {
        bytes memory _message = Messages.formatDisallowInvestmentCurrency(poolId, currency);
        router.execute(_message);
    }

    function addTranche(
        uint64 poolId,
        bytes16 trancheId,
        string memory tokenName,
        string memory tokenSymbol,
        uint8 decimals,
        uint8 restrictionSet
    ) public {
        bytes memory _message =
            Messages.formatAddTranche(poolId, trancheId, tokenName, tokenSymbol, decimals, restrictionSet);
        router.execute(_message);
    }

    function updateMember(uint64 poolId, bytes16 trancheId, address user, uint64 validUntil) public {
        bytes memory _message = Messages.formatUpdateMember(poolId, trancheId, user, validUntil);
        router.execute(_message);
    }

    function updateTrancheTokenMetadata(
        uint64 poolId,
        bytes16 trancheId,
        string memory tokenName,
        string memory tokenSymbol
    ) public {
        bytes memory _message = Messages.formatUpdateTrancheTokenMetadata(poolId, trancheId, tokenName, tokenSymbol);
        router.execute(_message);
    }

    function updateTrancheTokenPrice(
        uint64 poolId,
        bytes16 trancheId,
        uint128 currencyId,
        uint128 price,
        uint64 computedAt
    ) public {
        bytes memory _message = Messages.formatUpdateTrancheTokenPrice(poolId, trancheId, currencyId, price, computedAt);
        router.execute(_message);
    }

    function triggerIncreaseRedeemOrder(
        uint64 poolId,
        bytes16 trancheId,
        address investor,
        uint128 currencyId,
        uint128 amount
    ) public {
        bytes memory _message =
            Messages.formatTriggerIncreaseRedeemOrder(poolId, trancheId, bytes32(bytes20(investor)), currencyId, amount);
        router.execute(_message);
    }

    // Trigger an incoming (e.g. Centrifuge Chain -> EVM) transfer of stable coins
    function incomingTransfer(uint128 currency, bytes32 sender, bytes32 recipient, uint128 amount) public {
        bytes memory _message = Messages.formatTransfer(currency, sender, recipient, amount);
        router.execute(_message);
    }

    // Trigger an incoming (e.g. Centrifuge Chain -> EVM) transfer of tranche tokens
    function incomingTransferTrancheTokens(
        uint64 poolId,
        bytes16 trancheId,
        uint64 destinationChainId,
        address destinationAddress,
        uint128 amount
    ) public {
        bytes memory _message = Messages.formatTransferTrancheTokens(
            poolId,
            trancheId,
            bytes32(bytes20(msg.sender)),
            Messages.formatDomain(Messages.Domain.EVM, destinationChainId),
            destinationAddress,
            amount
        );
        router.execute(_message);
    }

    function incomingScheduleUpgrade(address target) public {
        bytes memory _message = Messages.formatScheduleUpgrade(target);
        router.execute(_message);
    }

    function incomingCancelUpgrade(address target) public {
        bytes memory _message = Messages.formatCancelUpgrade(target);
        router.execute(_message);
    }

    function freeze(uint64 poolId, bytes16 trancheId, address user) public {
        bytes memory _message = Messages.formatFreeze(poolId, trancheId, user);
        router.execute(_message);
    }

    function unfreeze(uint64 poolId, bytes16 trancheId, address user) public {
        bytes memory _message = Messages.formatUnfreeze(poolId, trancheId, user);
        router.execute(_message);
    }

    function isExecutedDecreaseInvestOrder(
        uint64 poolId,
        bytes16 trancheId,
        bytes32 investor,
        uint128 currency,
        uint128 currencyPayout,
        uint128 remainingInvestOrder
    ) public {
        bytes memory _message = Messages.formatExecutedDecreaseInvestOrder(
            poolId, trancheId, investor, currency, currencyPayout, remainingInvestOrder
        );
        router.execute(_message);
    }

    function isExecutedDecreaseRedeemOrder(
        uint64 poolId,
        bytes16 trancheId,
        bytes32 investor,
        uint128 currency,
        uint128 trancheTokensPayout,
        uint128 remainingRedeemOrder
    ) public {
        bytes memory _message = Messages.formatExecutedDecreaseRedeemOrder(
            poolId, trancheId, investor, currency, trancheTokensPayout, remainingRedeemOrder
        );
        router.execute(_message);
    }

    function isExecutedCollectInvest(
        uint64 poolId,
        bytes16 trancheId,
        bytes32 investor,
        uint128 currency,
        uint128 currencyPayout,
        uint128 trancheTokensPayout,
        uint128 remainingInvestOrder
    ) public {
        bytes memory _message = Messages.formatExecutedCollectInvest(
            poolId, trancheId, investor, currency, currencyPayout, trancheTokensPayout, remainingInvestOrder
        );
        router.execute(_message);
    }

    function isExecutedCollectRedeem(
        uint64 poolId,
        bytes16 trancheId,
        bytes32 investor,
        uint128 currency,
        uint128 currencyPayout,
        uint128 trancheTokensPayout,
        uint128 remainingRedeemOrder
    ) public {
        bytes memory _message = Messages.formatExecutedCollectRedeem(
            poolId, trancheId, investor, currency, currencyPayout, trancheTokensPayout, remainingRedeemOrder
        );
        router.execute(_message);
    }

    function dispatch(
        uint32 _destinationDomain,
        uint256 _destinationChainId,
        bytes32 _recipientAddress,
        bytes memory _messageBody
    ) external {
        dispatchCalls++;
        dispatchDomain = _destinationDomain;
        dispatchChainId = _destinationChainId;
        dispatchMessage = _messageBody;
        dispatchRecipient = _recipientAddress;
    }

    // Added to be ignored in coverage report
    function test() public {}
}
