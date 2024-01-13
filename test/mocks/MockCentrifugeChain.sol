// SPDw-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import {MessagesLib} from "src/libraries/MessagesLib.sol";
import "forge-std/Test.sol";

interface RouterLike {
    function execute(bytes memory _message) external;
}

contract MockCentrifugeChain is Test {
    address[] public routers;

    constructor(address[] memory routers_) {
        for (uint i = 0; i < routers_.length; i++) {
            routers.push(routers_[i]);
        }
    }

    function addCurrency(uint128 currency, address currencyAddress) public {
        bytes memory _message = MessagesLib.formatAddCurrency(currency, currencyAddress);
        _execute(_message);
    }

    function addPool(uint64 poolId) public {
        bytes memory _message = MessagesLib.formatAddPool(poolId);
        _execute(_message);
    }

    function allowInvestmentCurrency(uint64 poolId, uint128 currency) public {
        bytes memory _message = MessagesLib.formatAllowInvestmentCurrency(poolId, currency);
        _execute(_message);
    }

    function disallowInvestmentCurrency(uint64 poolId, uint128 currency) public {
        bytes memory _message = MessagesLib.formatDisallowInvestmentCurrency(poolId, currency);
        _execute(_message);
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
            MessagesLib.formatAddTranche(poolId, trancheId, tokenName, tokenSymbol, decimals, restrictionSet);
        _execute(_message);
    }

    function updateMember(uint64 poolId, bytes16 trancheId, address user, uint64 validUntil) public {
        bytes memory _message = MessagesLib.formatUpdateMember(poolId, trancheId, user, validUntil);
        _execute(_message);
    }

    function updateTrancheTokenMetadata(
        uint64 poolId,
        bytes16 trancheId,
        string memory tokenName,
        string memory tokenSymbol
    ) public {
        bytes memory _message = MessagesLib.formatUpdateTrancheTokenMetadata(poolId, trancheId, tokenName, tokenSymbol);
        _execute(_message);
    }

    function updateTrancheTokenPrice(
        uint64 poolId,
        bytes16 trancheId,
        uint128 currencyId,
        uint128 price,
        uint64 computedAt
    ) public {
        bytes memory _message =
            MessagesLib.formatUpdateTrancheTokenPrice(poolId, trancheId, currencyId, price, computedAt);
        _execute(_message);
    }

    function triggerIncreaseRedeemOrder(
        uint64 poolId,
        bytes16 trancheId,
        address investor,
        uint128 currencyId,
        uint128 amount
    ) public {
        bytes memory _message = MessagesLib.formatTriggerIncreaseRedeemOrder(
            poolId, trancheId, bytes32(bytes20(investor)), currencyId, amount
        );
        _execute(_message);
    }

    // Trigger an incoming (e.g. Centrifuge Chain -> EVM) transfer of stable coins
    function incomingTransfer(uint128 currency, bytes32 sender, bytes32 recipient, uint128 amount) public {
        bytes memory _message = MessagesLib.formatTransfer(currency, sender, recipient, amount);
        _execute(_message);
    }

    // Trigger an incoming (e.g. Centrifuge Chain -> EVM) transfer of tranche tokens
    function incomingTransferTrancheTokens(
        uint64 poolId,
        bytes16 trancheId,
        uint64 destinationChainId,
        address destinationAddress,
        uint128 amount
    ) public {
        bytes memory _message = MessagesLib.formatTransferTrancheTokens(
            poolId,
            trancheId,
            bytes32(bytes20(msg.sender)),
            MessagesLib.formatDomain(MessagesLib.Domain.EVM, destinationChainId),
            destinationAddress,
            amount
        );
        _execute(_message);
    }

    function incomingScheduleUpgrade(address target) public {
        bytes memory _message = MessagesLib.formatScheduleUpgrade(target);
        _execute(_message);
    }

    function incomingCancelUpgrade(address target) public {
        bytes memory _message = MessagesLib.formatCancelUpgrade(target);
        _execute(_message);
    }

    function freeze(uint64 poolId, bytes16 trancheId, address user) public {
        bytes memory _message = MessagesLib.formatFreeze(poolId, trancheId, user);
        _execute(_message);
    }

    function unfreeze(uint64 poolId, bytes16 trancheId, address user) public {
        bytes memory _message = MessagesLib.formatUnfreeze(poolId, trancheId, user);
        _execute(_message);
    }

    function isExecutedDecreaseInvestOrder(
        uint64 poolId,
        bytes16 trancheId,
        bytes32 investor,
        uint128 currency,
        uint128 currencyPayout,
        uint128 remainingInvestOrder
    ) public {
        bytes memory _message = MessagesLib.formatExecutedDecreaseInvestOrder(
            poolId, trancheId, investor, currency, currencyPayout, remainingInvestOrder
        );
        _execute(_message);
    }

    function isExecutedDecreaseRedeemOrder(
        uint64 poolId,
        bytes16 trancheId,
        bytes32 investor,
        uint128 currency,
        uint128 trancheTokensPayout,
        uint128 remainingRedeemOrder
    ) public {
        bytes memory _message = MessagesLib.formatExecutedDecreaseRedeemOrder(
            poolId, trancheId, investor, currency, trancheTokensPayout, remainingRedeemOrder
        );
        _execute(_message);
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
        bytes memory _message = MessagesLib.formatExecutedCollectInvest(
            poolId, trancheId, investor, currency, currencyPayout, trancheTokensPayout, remainingInvestOrder
        );
        _execute(_message);
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
        bytes memory _message = MessagesLib.formatExecutedCollectRedeem(
            poolId, trancheId, investor, currency, currencyPayout, trancheTokensPayout, remainingRedeemOrder
        );
        _execute(_message);
    }

    function _execute(bytes memory message) internal {
        bytes memory proof = MessagesLib.formatMessageProof(message);
        for (uint i = 0; i < routers.length; i++) {
            RouterLike(routers[i]).execute(i == 0 ? message : proof);
        }
    }

    // Added to be ignored in coverage report
    function test() public {}
}
