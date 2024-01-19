// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import {BytesLib} from "src/libraries/BytesLib.sol";
import {CastLib} from "src/libraries/CastLib.sol";

/// @title  MessagesLib
/// @dev    Library for encoding and decoding messages.
library MessagesLib {
    using BytesLib for bytes;
    using CastLib for *;

    enum Call {
        /// 0 - An invalid message
        Invalid,
        /// 1 - Add a currency id -> EVM address mapping
        AddCurrency,
        /// 2 - Add Pool
        AddPool,
        /// 3 - Allow a currency to be used as a currency for investing in pools
        AllowInvestmentCurrency,
        /// 4 - Add a Pool's Tranche Token
        AddTranche,
        /// 5 - Update the price of a Tranche Token
        UpdateTrancheTokenPrice,
        /// 6 - Update the member list of a tranche token with a new member
        UpdateMember,
        /// 7 - A transfer of currency
        Transfer,
        /// 8 - A transfer of tranche tokens
        TransferTrancheTokens,
        /// 9 - Increase an investment order by a given amount
        IncreaseInvestOrder,
        /// 10 - Decrease an investment order by a given amount
        DecreaseInvestOrder,
        /// 11 - Increase a Redeem order by a given amount
        IncreaseRedeemOrder,
        /// 12 - Decrease a Redeem order by a given amount
        DecreaseRedeemOrder,
        /// 13 - Collect investment
        DEPRECATED_CollectInvest,
        /// 14 - Collect Redeem
        DEPRECATED_CollectRedeem,
        /// 15 - Executed Decrease Invest Order
        ExecutedDecreaseInvestOrder,
        /// 16 - Executed Decrease Redeem Order
        ExecutedDecreaseRedeemOrder,
        /// 17 - Executed Collect Invest
        ExecutedCollectInvest,
        /// 18 - Executed Collect Redeem
        ExecutedCollectRedeem,
        /// 19 - Cancel an investment order
        CancelInvestOrder,
        /// 20 - Cancel a redeem order
        CancelRedeemOrder,
        /// 21 - Schedule an upgrade contract to be granted admin rights
        ScheduleUpgrade,
        /// 22 - Cancel a previously scheduled upgrade
        CancelUpgrade,
        /// 23 - Update tranche token metadata
        UpdateTrancheTokenMetadata,
        /// 24 - Disallow a currency to be used as a currency for investing in pools
        DisallowInvestmentCurrency,
        /// 25 - Freeze tranche tokens
        Freeze,
        /// 26 - Unfreeze tranche tokens
        Unfreeze,
        /// 27 - Request redeem investor
        TriggerIncreaseRedeemOrder,
        /// 28 - Proof
        MessageProof,
        /// 29 - Initiate Message Recovery
        InitiateMessageRecovery,
        /// 30 - Dispute Message Recovery
        DisputeMessageRecovery
    }

    enum Domain {
        Centrifuge,
        EVM
    }

    function messageType(bytes memory _msg) internal pure returns (Call _call) {
        _call = Call(_msg.toUint8(0));
    }

    /**
     * 0: call type (uint8 = 1 byte)
     * 1-16: The Liquidity Pool's global currency id (uint128 = 16 bytes)
     * 17-36: The EVM address of the currency (address = 20 bytes)
     */
    function parseAddCurrency(bytes memory _msg) internal pure returns (uint128 currency, address currencyAddress) {
        currency = _msg.toUint128(1);
        currencyAddress = _msg.toAddress(17);
    }

    /**
     * 0: call type (uint8 = 1 byte)
     * 1-8: poolId (uint64 = 8 bytes)
     */
    function parseAddPool(bytes memory _msg) internal pure returns (uint64 poolId) {
        poolId = _msg.toUint64(1);
    }

    /**
     * 0: call type (uint8 = 1 byte)
     * 1-8: poolId (uint64 = 8 bytes)
     * 9-24: currency (uint128 = 16 bytes)
     */
    function parseAllowInvestmentCurrency(bytes memory _msg) internal pure returns (uint64 poolId, uint128 currency) {
        poolId = _msg.toUint64(1);
        currency = _msg.toUint128(9);
    }

    /**
     * 0: call type (uint8 = 1 byte)
     * 1-8: poolId (uint64 = 8 bytes)
     * 9-24: trancheId (16 bytes)
     * 25-152: tokenName (string = 128 bytes)
     * 153-184: tokenSymbol (string = 32 bytes)
     * 185: decimals (uint8 = 1 byte)
     * 186: restriction set (uint8 = 1 byte)
     */
    function parseAddTranche(bytes memory _msg)
        internal
        pure
        returns (
            uint64 poolId,
            bytes16 trancheId,
            string memory tokenName,
            string memory tokenSymbol,
            uint8 decimals,
            uint8 restrictionSet
        )
    {
        poolId = _msg.toUint64(1);
        trancheId = _msg.toBytes16(9);
        tokenName = _msg.slice(25, 128).bytes128ToString();
        tokenSymbol = _msg.toBytes32(153).toString();
        decimals = _msg.toUint8(185);
        restrictionSet = _msg.toUint8(186);
    }

    /**
     * 0: call type (uint8 = 1 byte)
     * 1-8: poolId (uint64 = 8 bytes)
     * 9-24: trancheId (16 bytes)
     * 25-45: user (Ethereum address, 20 bytes - Skip 12 bytes from 32-byte addresses)
     * 57-65: validUntil (uint64 = 8 bytes)
     *
     */
    function parseUpdateMember(bytes memory _msg)
        internal
        pure
        returns (uint64 poolId, bytes16 trancheId, address user, uint64 validUntil)
    {
        poolId = _msg.toUint64(1);
        trancheId = _msg.toBytes16(9);
        user = _msg.toAddress(25);
        validUntil = _msg.toUint64(57);
    }

    /**
     * 0: call type (uint8 = 1 byte)
     * 1-8: poolId (uint64 = 8 bytes)
     * 9-24: trancheId (16 bytes)
     * 25-40: currency (uint128 = 16 bytes)
     * 41-56: price (uint128 = 16 bytes)
     * 57-64: computedAt (uint64 = 8 bytes)
     */
    function parseUpdateTrancheTokenPrice(bytes memory _msg)
        internal
        pure
        returns (uint64, bytes16, uint128, uint128, uint64)
    {
        return (_msg.toUint64(1), _msg.toBytes16(9), _msg.toUint128(25), _msg.toUint128(41), _msg.toUint64(57));
    }

    /*
     * 0: call type (uint8 = 1 byte)
     * 1-16: currency (uint128 = 16 bytes)
     * 17-48: sender address (32 bytes)
     * 49-80: receiver address (32 bytes)
     * 81-96: amount (uint128 = 16 bytes)
     */
    function parseTransfer(bytes memory _msg)
        internal
        pure
        returns (uint128 currency, bytes32 sender, bytes32 receiver, uint128 amount)
    {
        currency = _msg.toUint128(1);
        sender = _msg.toBytes32(17);
        receiver = _msg.toBytes32(49);
        amount = _msg.toUint128(81);
    }

    // An optimised `parseTransfer` function that saves gas by ignoring the `sender` field and that
    // parses and returns the `recipient` as an `address` instead of the `bytes32` the message holds.
    function parseIncomingTransfer(bytes memory _msg)
        internal
        pure
        returns (uint128 currency, address recipient, uint128 amount)
    {
        currency = _msg.toUint128(1);
        recipient = _msg.toAddress(49);
        amount = _msg.toUint128(81);
    }

    /**
     * 0: call type (uint8 = 1 byte)
     * 1-8: poolId (uint64 = 8 bytes)
     * 9-24: trancheId (16 bytes)
     * 25-56: sender (bytes32)
     * 57-65: destinationDomain ((Domain: u8, ChainId: u64) =  9 bytes total)
     * 66-97: destinationAddress (32 bytes - Either a Centrifuge address or an EVM address followed by 12 zeros)
     * 98-113: amount (uint128 = 16 bytes)
     */
    // Parse a TransferTrancheTokens to an EVM-based `destinationAddress` (20-byte long).
    // We ignore the `sender` and the `domain` since it's not relevant when parsing an incoming message.
    function parseTransferTrancheTokens20(bytes memory _msg)
        internal
        pure
        returns (uint64 poolId, bytes16 trancheId, address destinationAddress, uint128 amount)
    {
        poolId = _msg.toUint64(1);
        trancheId = _msg.toBytes16(9);
        // ignore: `sender` at bytes 25-56
        // ignore: `domain` at bytes 57-65
        destinationAddress = _msg.toAddress(66);
        amount = _msg.toUint128(98);
    }

    /*
     * 0: call type (uint8 = 1 byte)
     * 1-8: poolId (uint64 = 8 bytes)
     * 9-24: trancheId (16 bytes)
     * 25-56: investor address (32 bytes)
     * 57-72: currency (uint128 = 16 bytes)
     * 73-89: amount (uint128 = 16 bytes)
     */
    function parseIncreaseInvestOrder(bytes memory _msg)
        internal
        pure
        returns (uint64 poolId, bytes16 trancheId, bytes32 investor, uint128 currency, uint128 amount)
    {
        poolId = _msg.toUint64(1);
        trancheId = _msg.toBytes16(9);
        investor = _msg.toBytes32(25);
        currency = _msg.toUint128(57);
        amount = _msg.toUint128(73);
    }

    /*
     * 0: call type (uint8 = 1 byte)
     * 1-8: poolId (uint64 = 8 bytes)
     * 9-24: trancheId (16 bytes)
     * 25-56: investor address (32 bytes)
     * 57-72: currency (uint128 = 16 bytes)
     * 73-89: amount (uint128 = 16 bytes)
     */
    function parseDecreaseInvestOrder(bytes memory _msg)
        internal
        pure
        returns (uint64 poolId, bytes16 trancheId, bytes32 investor, uint128 currency, uint128 amount)
    {
        return parseIncreaseInvestOrder(_msg);
    }

    /*
     * 0: call type (uint8 = 1 byte)
     * 1-8: poolId (uint64 = 8 bytes)
     * 9-24: trancheId (16 bytes)
     * 25-56: investor address (32 bytes)
     * 57-72: currency (uint128 = 16 bytes)
     * 73-89: amount (uint128 = 16 bytes)
     */
    function parseIncreaseRedeemOrder(bytes memory _msg)
        internal
        pure
        returns (uint64 poolId, bytes16 trancheId, bytes32 investor, uint128 currency, uint128 amount)
    {
        return parseIncreaseInvestOrder(_msg);
    }

    /*
     * 0: call type (uint8 = 1 byte)
     * 1-8: poolId (uint64 = 8 bytes)
     * 9-24: trancheId (16 bytes)
     * 25-56: investor address (32 bytes)
     * 57-72: currency (uint128 = 16 bytes)
     * 73-89: amount (uint128 = 16 bytes)
     */
    function parseDecreaseRedeemOrder(bytes memory _msg)
        internal
        pure
        returns (uint64 poolId, bytes16 trancheId, bytes32 investor, uint128 currency, uint128 amount)
    {
        return parseDecreaseInvestOrder(_msg);
    }

    function formatExecutedDecreaseInvestOrder(
        uint64 poolId,
        bytes16 trancheId,
        bytes32 investor,
        uint128 currency,
        uint128 currencyPayout,
        uint128 remainingInvestOrder
    ) internal pure returns (bytes memory) {
        return abi.encodePacked(
            uint8(Call.ExecutedDecreaseInvestOrder),
            poolId,
            trancheId,
            investor,
            currency,
            currencyPayout,
            remainingInvestOrder
        );
    }

    function parseExecutedDecreaseInvestOrder(bytes memory _msg)
        internal
        pure
        returns (
            uint64 poolId,
            bytes16 trancheId,
            address investor,
            uint128 currency,
            uint128 trancheTokenPayout,
            uint128 remainingInvestOrder
        )
    {
        poolId = _msg.toUint64(1);
        trancheId = _msg.toBytes16(9);
        investor = _msg.toAddress(25);
        currency = _msg.toUint128(57);
        trancheTokenPayout = _msg.toUint128(73);
        remainingInvestOrder = _msg.toUint128(89);
    }

    function formatExecutedDecreaseRedeemOrder(
        uint64 poolId,
        bytes16 trancheId,
        bytes32 investor,
        uint128 currency,
        uint128 trancheTokenPayout,
        uint128 remainingRedeemOrder
    ) internal pure returns (bytes memory) {
        return abi.encodePacked(
            uint8(Call.ExecutedDecreaseRedeemOrder),
            poolId,
            trancheId,
            investor,
            currency,
            trancheTokenPayout,
            remainingRedeemOrder
        );
    }

    function parseExecutedDecreaseRedeemOrder(bytes memory _msg)
        internal
        pure
        returns (
            uint64 poolId,
            bytes16 trancheId,
            address investor,
            uint128 currency,
            uint128 trancheTokensPayout,
            uint128 remainingRedeemOrder
        )
    {
        poolId = _msg.toUint64(1);
        trancheId = _msg.toBytes16(9);
        investor = _msg.toAddress(25);
        currency = _msg.toUint128(57);
        trancheTokensPayout = _msg.toUint128(73);
        remainingRedeemOrder = _msg.toUint128(89);
    }

    function formatExecutedCollectInvest(
        uint64 poolId,
        bytes16 trancheId,
        bytes32 investor,
        uint128 currency,
        uint128 currencyPayout,
        uint128 trancheTokensPayout,
        uint128 remainingInvestOrder
    ) internal pure returns (bytes memory) {
        return abi.encodePacked(
            uint8(Call.ExecutedCollectInvest),
            poolId,
            trancheId,
            investor,
            currency,
            currencyPayout,
            trancheTokensPayout,
            remainingInvestOrder
        );
    }

    function parseExecutedCollectInvest(bytes memory _msg)
        internal
        pure
        returns (
            uint64 poolId,
            bytes16 trancheId,
            address investor,
            uint128 currency,
            uint128 currencyPayout,
            uint128 trancheTokensPayout,
            uint128 remainingInvestOrder
        )
    {
        poolId = _msg.toUint64(1);
        trancheId = _msg.toBytes16(9);
        investor = _msg.toAddress(25);
        currency = _msg.toUint128(57);
        currencyPayout = _msg.toUint128(73);
        trancheTokensPayout = _msg.toUint128(89);
        remainingInvestOrder = _msg.toUint128(105);
    }

    function formatExecutedCollectRedeem(
        uint64 poolId,
        bytes16 trancheId,
        bytes32 investor,
        uint128 currency,
        uint128 currencyPayout,
        uint128 trancheTokensPayout,
        uint128 remainingRedeemOrder
    ) internal pure returns (bytes memory) {
        return abi.encodePacked(
            uint8(Call.ExecutedCollectRedeem),
            poolId,
            trancheId,
            investor,
            currency,
            currencyPayout,
            trancheTokensPayout,
            remainingRedeemOrder
        );
    }

    function parseExecutedCollectRedeem(bytes memory _msg)
        internal
        pure
        returns (
            uint64 poolId,
            bytes16 trancheId,
            address investor,
            uint128 currency,
            uint128 currencyPayout,
            uint128 trancheTokensPayout,
            uint128 remainingRedeemOrder
        )
    {
        poolId = _msg.toUint64(1);
        trancheId = _msg.toBytes16(9);
        investor = _msg.toAddress(25);
        currency = _msg.toUint128(57);
        currencyPayout = _msg.toUint128(73);
        trancheTokensPayout = _msg.toUint128(89);
        remainingRedeemOrder = _msg.toUint128(105);
    }

    function formatScheduleUpgrade(address _contract) internal pure returns (bytes memory) {
        return abi.encodePacked(uint8(Call.ScheduleUpgrade), _contract);
    }

    function parseScheduleUpgrade(bytes memory _msg) internal pure returns (address _contract) {
        _contract = _msg.toAddress(1);
    }

    function formatCancelUpgrade(address _contract) internal pure returns (bytes memory) {
        return abi.encodePacked(uint8(Call.CancelUpgrade), _contract);
    }

    function parseCancelUpgrade(bytes memory _msg) internal pure returns (address _contract) {
        _contract = _msg.toAddress(1);
    }

    /**
     * 0: call type (uint8 = 1 byte)
     * 1-8: poolId (uint64 = 8 bytes)
     * 9-24: trancheId (16 bytes)
     * 25-152: tokenName (string = 128 bytes)
     * 153-184: tokenSymbol (string = 32 bytes)
     */
    function parseUpdateTrancheTokenMetadata(bytes memory _msg)
        internal
        pure
        returns (uint64 poolId, bytes16 trancheId, string memory tokenName, string memory tokenSymbol)
    {
        poolId = _msg.toUint64(1);
        trancheId = _msg.toBytes16(9);
        tokenName = _msg.slice(25, 128).bytes128ToString();
        tokenSymbol = _msg.toBytes32(153).toString();
    }

    function parseCancelInvestOrder(bytes memory _msg)
        internal
        pure
        returns (uint64 poolId, bytes16 trancheId, address investor, uint128 currency)
    {
        poolId = _msg.toUint64(1);
        trancheId = _msg.toBytes16(9);
        investor = _msg.toAddress(25);
        currency = _msg.toUint128(57);
    }

    function parseCancelRedeemOrder(bytes memory _msg)
        internal
        pure
        returns (uint64 poolId, bytes16 trancheId, address investor, uint128 currency)
    {
        poolId = _msg.toUint64(1);
        trancheId = _msg.toBytes16(9);
        investor = _msg.toAddress(25);
        currency = _msg.toUint128(57);
    }

    /**
     * 0: call type (uint8 = 1 byte)
     * 1-8: poolId (uint64 = 8 bytes)
     * 9-24: currency (uint128 = 16 bytes)
     */
    function parseDisallowInvestmentCurrency(bytes memory _msg)
        internal
        pure
        returns (uint64 poolId, uint128 currency)
    {
        poolId = _msg.toUint64(1);
        currency = _msg.toUint128(9);
    }

    /**
     * 0: call type (uint8 = 1 byte)
     * 1-8: poolId (uint64 = 8 bytes)
     * 9-24: trancheId (16 bytes)
     * 25-45: user (Ethereum address, 20 bytes - Skip 12 bytes from 32-byte addresses)
     *
     */
    function formatFreeze(uint64 poolId, bytes16 trancheId, address member) internal pure returns (bytes memory) {
        return abi.encodePacked(uint8(Call.Freeze), poolId, trancheId, member.toBytes32());
    }

    function parseFreeze(bytes memory _msg) internal pure returns (uint64 poolId, bytes16 trancheId, address user) {
        poolId = _msg.toUint64(1);
        trancheId = _msg.toBytes16(9);
        user = _msg.toAddress(25);
    }

    /**
     * 0: call type (uint8 = 1 byte)
     * 1-8: poolId (uint64 = 8 bytes)
     * 9-24: trancheId (16 bytes)
     * 25-45: user (Ethereum address, 20 bytes - Skip 12 bytes from 32-byte addresses)
     *
     */
    function formatUnfreeze(uint64 poolId, bytes16 trancheId, address user) internal pure returns (bytes memory) {
        return abi.encodePacked(uint8(Call.Unfreeze), poolId, trancheId, user.toBytes32());
    }

    function parseUnfreeze(bytes memory _msg) internal pure returns (uint64 poolId, bytes16 trancheId, address user) {
        poolId = _msg.toUint64(1);
        trancheId = _msg.toBytes16(9);
        user = _msg.toAddress(25);
    }

    /*
     * 0: call type (uint8 = 1 byte)
     * 1-8: poolId (uint64 = 8 bytes)
     * 9-24: trancheId (16 bytes)
     * 25-56: investor address (32 bytes)
     * 57-72: currency (uint128 = 16 bytes)
     * 73-89: amount (uint128 = 16 bytes)
     */
    function formatTriggerIncreaseRedeemOrder(
        uint64 poolId,
        bytes16 trancheId,
        bytes32 investor,
        uint128 currency,
        uint128 trancheTokenAmount
    ) internal pure returns (bytes memory) {
        return abi.encodePacked(
            uint8(Call.TriggerIncreaseRedeemOrder), poolId, trancheId, investor, currency, trancheTokenAmount
        );
    }

    function parseTriggerIncreaseRedeemOrder(bytes memory _msg)
        internal
        pure
        returns (uint64 poolId, bytes16 trancheId, address investor, uint128 currency, uint128 trancheTokenAmount)
    {
        poolId = _msg.toUint64(1);
        trancheId = _msg.toBytes16(9);
        investor = _msg.toAddress(25);
        currency = _msg.toUint128(57);
        trancheTokenAmount = _msg.toUint128(73);
    }

    /**
     * 0: call type (uint8 = 1 byte)
     * 1-32: The keccak message proof (bytes32)
     */
    function formatMessageProof(bytes memory message) internal pure returns (bytes memory) {
        return abi.encodePacked(uint8(Call.MessageProof), keccak256(message));
    }

    function formatMessageProof(bytes32 messageHash) internal pure returns (bytes memory) {
        return abi.encodePacked(uint8(Call.MessageProof), messageHash);
    }

    function parseMessageProof(bytes memory _msg) internal pure returns (bytes32 proof) {
        proof = _msg.toBytes32(1);
    }

    /**
     * Initiate Message Recovery
     *
     * 0: call type (uint8 = 1 byte)
     * 1-32: The message hash (32 bytes)
     * 33-52: The router address (32 bytes)
     */
    function formatInitiateMessageRecovery(bytes memory message, address router) internal pure returns (bytes memory) {
        return abi.encodePacked(uint8(Call.InitiateMessageRecovery), keccak256(message), router.toBytes32());
    }

    function parseInitiateMessageRecovery(bytes memory _msg)
        internal
        pure
        returns (bytes32 messageHash, address router)
    {
        messageHash = BytesLib.toBytes32(_msg, 1);
        router = BytesLib.toAddress(_msg, 33);
    }

    /**
     * Dispute Message Recovery
     *
     * 0: call type (uint8 = 1 byte)
     * 1-32: Message hash (32 bytes)
     */
    function formatDisputeMessageRecovery(bytes memory message) internal pure returns (bytes memory) {
        return abi.encodePacked(uint8(Call.DisputeMessageRecovery), keccak256(message));
    }

    function parseDisputeMessageRecovery(bytes memory _msg) internal pure returns (bytes32 messageHash) {
        messageHash = BytesLib.toBytes32(_msg, 1);
    }

    function isRecoveryMessage(bytes memory _msg) internal pure returns (bool) {
        return messageType(_msg) == Call.InitiateMessageRecovery || messageType(_msg) == Call.DisputeMessageRecovery;
    }

    // Utils
    function formatDomain(Domain domain) public pure returns (bytes9) {
        return bytes9(bytes1(uint8(domain)));
    }

    function formatDomain(Domain domain, uint64 chainId) public pure returns (bytes9) {
        return bytes9(BytesLib.slice(abi.encodePacked(uint8(domain), chainId), 0, 9));
    }
}
