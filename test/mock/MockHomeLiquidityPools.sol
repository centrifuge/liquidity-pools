// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.18;
pragma abicoder v2;

import {TypedMemView} from "memview-sol/TypedMemView.sol";
import {Messages} from "src/gateway/Messages.sol";
import "forge-std/Test.sol";
import {XCMRouter} from "src/gateway/routers/xcm/Router.sol";

interface XcmRouterLike {
    function handle(bytes memory _message) external;
    function send(bytes memory message) external;
}

contract MockHomeLiquidityPools is Test {
    using TypedMemView for bytes;
    using TypedMemView for bytes29;
    using Messages for bytes29;

    XcmRouterLike public immutable router;

    uint32 immutable CENTRIFUGE_CHAIN_DOMAIN = 3000;
    uint32 immutable NONCE = 1;

    uint32 public dispatchDomain;
    uint256 public dispatchChainId;
    bytes public dispatchMessage;
    bytes32 public dispatchRecipient;
    uint256 public dispatchCalls;

    enum Types {AddPool}

    constructor(address xcmRouter) {
        router = XcmRouterLike(xcmRouter);
    }

    function addCurrency(uint128 currency, address currencyAddress) public {
        bytes memory _message = Messages.formatAddCurrency(currency, currencyAddress);
        router.handle(_message);
    }

    function addPool(uint64 poolId) public {
        bytes memory _message = Messages.formatAddPool(poolId);
        router.handle(_message);
    }

    function allowPoolCurrency(uint64 poolId, uint128 currency) public {
        bytes memory _message = Messages.formatAllowPoolCurrency(poolId, currency);
        router.handle(_message);
    }

    function addTranche(
        uint64 poolId,
        bytes16 trancheId,
        string memory tokenName,
        string memory tokenSymbol,
        uint8 decimals,
        uint128 price
    ) public {
        bytes memory _message = Messages.formatAddTranche(poolId, trancheId, tokenName, tokenSymbol, decimals, price);
        router.handle(_message);
    }

    function updateMember(uint64 poolId, bytes16 trancheId, address user, uint64 validUntil) public {
        bytes memory _message = Messages.formatUpdateMember(poolId, trancheId, user, validUntil);
        router.handle(_message);
    }

    function updateTrancheTokenMetadata(
        uint64 poolId,
        bytes16 trancheId,
        string memory tokenName,
        string memory tokenSymbol
    ) public {
        bytes memory _message = Messages.formatUpdateTrancheTokenMetadata(poolId, trancheId, tokenName, tokenSymbol);
        router.handle(_message);
    }

    function updateTrancheTokenPrice(uint64 poolId, bytes16 trancheId, uint128 price) public {
        bytes memory _message = Messages.formatUpdateTrancheTokenPrice(poolId, trancheId, price);
        router.handle(_message);
    }

    // Trigger an incoming (e.g. Centrifuge Chain -> EVM) transfer of stable coins
    function incomingTransfer(uint128 currency, bytes32 sender, bytes32 recipient, uint128 amount) public {
        bytes memory _message = Messages.formatTransfer(currency, sender, recipient, amount);
        router.handle(_message);
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
        router.handle(_message);
    }

    function incomingScheduleUpgrade(address spell) public {
        bytes memory _message = Messages.formatScheduleUpgrade(spell);
        router.handle(_message);
    }

    function incomingExecutedCollectInvest(
        uint64 poolId,
        bytes16 trancheId,
        bytes32 investor,
        uint128 currency,
        uint128 currencyPayout,
        uint128 trancheTokensPayout
    ) public {
        bytes memory _message = Messages.formatExecutedCollectInvest(
            poolId, trancheId, investor, currency, currencyPayout, trancheTokensPayout
        );
        router.handle(_message);
    }

    function incomingExecutedCollectRedeem(
        uint64 poolId,
        bytes16 trancheId,
        bytes32 investor,
        uint128 currency,
        uint128 currencyPayout,
        uint128 trancheTokensPayout
    ) public {
        bytes memory _message = Messages.formatExecutedCollectRedeem(
            poolId, trancheId, investor, currency, currencyPayout, trancheTokensPayout
        );
        router.handle(_message);
    }

    function incomingExecutedDecreaseInvestOrder(
        uint64 poolId,
        bytes16 trancheId,
        bytes32 investor,
        uint128 currency,
        uint128 currencyPayout,
        uint128 remainingInvestOrder
    ) public {
        bytes memory _message = Messages.formatExecutedDecreaseInvestOrder(
            poolId, trancheId, investor, currency, currencyPayout
        );
        router.handle(_message);
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
