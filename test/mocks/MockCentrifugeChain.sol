// SPDw-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import {MessagesLib} from "src/libraries/MessagesLib.sol";
import {CastLib} from "src/libraries/CastLib.sol";
import "forge-std/Test.sol";

interface RouterLike {
    function execute(bytes memory _message) external;
}

contract MockCentrifugeChain is Test {
    using CastLib for *;

    address[] public routers;

    constructor(address[] memory routers_) {
        for (uint256 i = 0; i < routers_.length; i++) {
            routers.push(routers_[i]);
        }
    }

    function addAsset(uint128 assetId, address asset) public {
        bytes memory _message = abi.encodePacked(uint8(MessagesLib.Call.AddAsset), assetId, asset);
        _execute(_message);
    }

    function addPool(uint64 poolId) public {
        bytes memory _message = abi.encodePacked(uint8(MessagesLib.Call.AddPool), poolId);
        _execute(_message);
    }

    function batchAddPoolAllowAsset(uint64 poolId, uint128 assetId) public {
        bytes memory _addPool = abi.encodePacked(uint8(MessagesLib.Call.AddPool), poolId);
        bytes memory _allowAsset = abi.encodePacked(uint8(MessagesLib.Call.AllowAsset), poolId, assetId);

        bytes memory _message = abi.encodePacked(
            uint8(MessagesLib.Call.Batch), uint8(_addPool.length), _addPool, uint8(_allowAsset.length), _allowAsset
        );
        _execute(_message);
    }

    function allowAsset(uint64 poolId, uint128 assetId) public {
        bytes memory _message = abi.encodePacked(uint8(MessagesLib.Call.AllowAsset), poolId, assetId);
        _execute(_message);
    }

    function disallowAsset(uint64 poolId, uint128 assetId) public {
        bytes memory _message = abi.encodePacked(uint8(MessagesLib.Call.DisallowAsset), poolId, assetId);
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
        bytes memory _message = abi.encodePacked(
            uint8(MessagesLib.Call.AddTranche),
            poolId,
            trancheId,
            tokenName.toBytes128(),
            tokenSymbol.toBytes32(),
            decimals,
            restrictionSet
        );
        _execute(_message);
    }

    function updateMember(uint64 poolId, bytes16 trancheId, address user, uint64 validUntil) public {
        bytes memory _message =
            abi.encodePacked(uint8(MessagesLib.Call.UpdateMember), poolId, trancheId, user.toBytes32(), validUntil);
        _execute(_message);
    }

    function updateTrancheTokenMetadata(
        uint64 poolId,
        bytes16 trancheId,
        string memory tokenName,
        string memory tokenSymbol
    ) public {
        bytes memory _message = abi.encodePacked(
            uint8(MessagesLib.Call.UpdateTrancheTokenMetadata),
            poolId,
            trancheId,
            tokenName.toBytes128(),
            tokenSymbol.toBytes32()
        );
        _execute(_message);
    }

    function updateTrancheTokenPrice(
        uint64 poolId,
        bytes16 trancheId,
        uint128 assetId,
        uint128 price,
        uint64 computedAt
    ) public {
        bytes memory _message = abi.encodePacked(
            uint8(MessagesLib.Call.UpdateTrancheTokenPrice), poolId, trancheId, assetId, price, computedAt
        );
        _execute(_message);
    }

    function triggerIncreaseRedeemOrder(
        uint64 poolId,
        bytes16 trancheId,
        address investor,
        uint128 assetId,
        uint128 amount
    ) public {
        bytes memory _message = abi.encodePacked(
            uint8(MessagesLib.Call.TriggerIncreaseRedeemOrder), poolId, trancheId, investor.toBytes32(), assetId, amount
        );
        _execute(_message);
    }

    // Trigger an incoming (e.g. Centrifuge Chain -> EVM) transfer of stable coins
    function incomingTransfer(uint128 assetId, bytes32 sender, bytes32 recipient, uint128 amount) public {
        bytes memory _message = abi.encodePacked(uint8(MessagesLib.Call.Transfer), assetId, sender, recipient, amount);
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
        bytes memory _message = abi.encodePacked(
            uint8(MessagesLib.Call.TransferTrancheTokens),
            poolId,
            trancheId,
            msg.sender.toBytes32(),
            MessagesLib.formatDomain(MessagesLib.Domain.EVM, destinationChainId),
            destinationAddress.toBytes32(),
            amount
        );
        _execute(_message);
    }

    function incomingScheduleUpgrade(address target) public {
        bytes memory _message = abi.encodePacked(uint8(MessagesLib.Call.ScheduleUpgrade), target);
        _execute(_message);
    }

    function incomingCancelUpgrade(address target) public {
        bytes memory _message = abi.encodePacked(uint8(MessagesLib.Call.CancelUpgrade), target);
        _execute(_message);
    }

    function freeze(uint64 poolId, bytes16 trancheId, address user) public {
        bytes memory _message = abi.encodePacked(uint8(MessagesLib.Call.Freeze), poolId, trancheId, user.toBytes32());
        _execute(_message);
    }

    function unfreeze(uint64 poolId, bytes16 trancheId, address user) public {
        bytes memory _message = abi.encodePacked(uint8(MessagesLib.Call.Unfreeze), poolId, trancheId, user.toBytes32());
        _execute(_message);
    }

    function recoverTokens(address target, address token, address to, uint256 amount) public {
        bytes memory _message = abi.encodePacked(
            uint8(MessagesLib.Call.RecoverTokens), target.toBytes32(), token.toBytes32(), to.toBytes32(), amount
        );
        _execute(_message);
    }

    function isFulfilledCancelDepositRequest(
        uint64 poolId,
        bytes16 trancheId,
        bytes32 investor,
        uint128 assetId,
        uint128 assets,
        uint128 fulfillment
    ) public {
        bytes memory _message = abi.encodePacked(
            uint8(MessagesLib.Call.FulfilledCancelDepositRequest),
            poolId,
            trancheId,
            investor,
            assetId,
            assets,
            fulfillment
        );
        _execute(_message);
    }

    function isFulfilledCancelRedeemRequest(
        uint64 poolId,
        bytes16 trancheId,
        bytes32 investor,
        uint128 assetId,
        uint128 shares,
        uint128 fulfillment
    ) public {
        bytes memory _message = abi.encodePacked(
            uint8(MessagesLib.Call.FulfilledCancelRedeemRequest),
            poolId,
            trancheId,
            investor,
            assetId,
            shares,
            fulfillment
        );
        _execute(_message);
    }

    function isFulfilledDepositRequest(
        uint64 poolId,
        bytes16 trancheId,
        bytes32 investor,
        uint128 assetId,
        uint128 assets,
        uint128 shares,
        uint128 fulfillment
    ) public {
        bytes memory _message = abi.encodePacked(
            uint8(MessagesLib.Call.FulfilledDepositRequest),
            poolId,
            trancheId,
            investor,
            assetId,
            assets,
            shares,
            fulfillment
        );
        _execute(_message);
    }

    function isFulfilledRedeemRequest(
        uint64 poolId,
        bytes16 trancheId,
        bytes32 investor,
        uint128 assetId,
        uint128 assets,
        uint128 shares
    ) public {
        bytes memory _message = abi.encodePacked(
            uint8(MessagesLib.Call.FulfilledRedeemRequest), poolId, trancheId, investor, assetId, assets, shares
        );
        _execute(_message);
    }

    function _execute(bytes memory message) internal {
        bytes memory proof = abi.encodePacked(uint8(MessagesLib.Call.MessageProof), keccak256(message));
        for (uint256 i = 0; i < routers.length; i++) {
            RouterLike(routers[i]).execute(i == 0 ? message : proof);
        }
    }

    // Added to be ignored in coverage report
    function test() public {}
}
