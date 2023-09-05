// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import {Messages} from "src/gateway/Messages.sol";
import "forge-std/Test.sol";
import {XCMRouter} from "src/gateway/routers/xcm/Router.sol";

interface XcmRouterLike {
    function execute(bytes memory _message) external;
    function send(bytes memory message) external;
}

contract MockHomeLiquidityPools is Test {
    XcmRouterLike public immutable router;

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
        router.execute(_message);
    }

    function addPool(uint64 poolId) public {
        bytes memory _message = Messages.formatAddPool(poolId);
        router.execute(_message);
    }

    function allowPoolCurrency(uint64 poolId, uint128 currency) public {
        bytes memory _message = Messages.formatAllowPoolCurrency(poolId, currency);
        router.execute(_message);
    }

    function addTranche(
        uint64 poolId,
        bytes16 trancheId,
        string memory tokenName,
        string memory tokenSymbol,
        uint8 decimals
    ) public {
        // TODO: remove price arg from the AddTranche message
        bytes memory _message = Messages.formatAddTranche(poolId, trancheId, tokenName, tokenSymbol, decimals, 0);
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

    function updateTrancheTokenPrice(uint64 poolId, bytes16 trancheId, uint128 currencyId, uint128 price) public {
        bytes memory _message = Messages.formatUpdateTrancheTokenPrice(poolId, trancheId, currencyId, price);
        router.execute(_message);
    }

    function updateTrancheInvestmentLimit(uint64 poolId, bytes16 trancheId, uint128 investmentLimit) public {
        bytes memory _message = Messages.formatUpdateTrancheInvestmentLimit(poolId, trancheId, investmentLimit);
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

    function isExecutedDecreaseInvestOrder(
        uint64 poolId,
        bytes16 trancheId,
        bytes32 investor,
        uint128 currency,
        uint128 currencyPayout
    ) public {
        bytes memory _message =
            Messages.formatExecutedDecreaseInvestOrder(poolId, trancheId, investor, currency, currencyPayout);
        router.execute(_message);
    }

    function isExecutedDecreaseRedeemOrder(
        uint64 poolId,
        bytes16 trancheId,
        bytes32 investor,
        uint128 currency,
        uint128 trancheTokensPayout
    ) public {
        bytes memory _message =
            Messages.formatExecutedDecreaseRedeemOrder(poolId, trancheId, investor, currency, trancheTokensPayout);
        router.execute(_message);
    }

    function isExecutedCollectInvest(
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
        router.execute(_message);
    }

    function isExecutedCollectRedeem(
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
