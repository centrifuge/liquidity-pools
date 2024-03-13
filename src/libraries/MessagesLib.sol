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
        DisputeMessageRecovery,
        /// 31 - Recover Tokens sent to the wrong contract
        RecoverTokens
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
    function parseAddCurrency(bytes memory _msg) internal pure returns (uint128 currencyId, address currencyAddress) {
        return (_msg.toUint128(1), _msg.toAddress(17));
    }

    /**
     * 0: call type (uint8 = 1 byte)
     * 1-8: poolId (uint64 = 8 bytes)
     */
    function parseAddPool(bytes memory _msg) internal pure returns (uint64 poolId) {
        return (_msg.toUint64(1));
    }

    /**
     * 0: call type (uint8 = 1 byte)
     * 1-8: poolId (uint64 = 8 bytes)
     * 9-24: currency (uint128 = 16 bytes)
     */
    function parseAllowInvestmentCurrency(bytes memory _msg)
        internal
        pure
        returns (uint64 poolId, uint128 currencyId)
    {
        return (_msg.toUint64(1), _msg.toUint128(9));
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
        return (
            _msg.toUint64(1),
            _msg.toBytes16(9),
            _msg.slice(25, 128).bytes128ToString(),
            _msg.toBytes32(153).toString(),
            _msg.toUint8(185),
            _msg.toUint8(186)
        );
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
        return (_msg.toUint64(1), _msg.toBytes16(9), _msg.toAddress(25), _msg.toUint64(57));
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
        returns (uint64 poolId, bytes16 trancheId, uint128 currencyId, uint128 price, uint64 computedAt)
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
        returns (uint128 currencyId, bytes32 sender, bytes32 receiver, uint128 amount)
    {
        return (_msg.toUint128(1), _msg.toBytes32(17), _msg.toBytes32(49), _msg.toUint128(81));
    }

    // An optimised `parseTransfer` function that saves gas by ignoring the `sender` field and that
    // parses and returns the `recipient` as an `address` instead of the `bytes32` the message holds.
    function parseIncomingTransfer(bytes memory _msg)
        internal
        pure
        returns (uint128 currencyId, address recipient, uint128 amount)
    {
        return (_msg.toUint128(1), _msg.toAddress(49), _msg.toUint128(81));
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
        // ignore: `sender` at bytes 25-56
        // ignore: `domain` at bytes 57-65
        return (_msg.toUint64(1), _msg.toBytes16(9), _msg.toAddress(66), _msg.toUint128(98));
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
        returns (uint64 poolId, bytes16 trancheId, bytes32 investor, uint128 currencyId, uint128 amount)
    {
        return (_msg.toUint64(1), _msg.toBytes16(9), _msg.toBytes32(25), _msg.toUint128(57), _msg.toUint128(73));
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
        returns (uint64 poolId, bytes16 trancheId, bytes32 investor, uint128 currencyId, uint128 amount)
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
        returns (uint64 poolId, bytes16 trancheId, bytes32 investor, uint128 currencyId, uint128 amount)
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
        returns (uint64 poolId, bytes16 trancheId, bytes32 investor, uint128 currencyId, uint128 amount)
    {
        return parseDecreaseInvestOrder(_msg);
    }

    function parseExecutedDecreaseInvestOrder(bytes memory _msg)
        internal
        pure
        returns (
            uint64 poolId,
            bytes16 trancheId,
            address investor,
            uint128 currencyId,
            uint128 trancheTokenPayout,
            uint128 remainingInvestOrder
        )
    {
        return (
            _msg.toUint64(1),
            _msg.toBytes16(9),
            _msg.toAddress(25),
            _msg.toUint128(57),
            _msg.toUint128(73),
            _msg.toUint128(89)
        );
    }

    function parseExecutedDecreaseRedeemOrder(bytes memory _msg)
        internal
        pure
        returns (
            uint64 poolId,
            bytes16 trancheId,
            address investor,
            uint128 currencyId,
            uint128 trancheTokensPayout,
            uint128 remainingRedeemOrder
        )
    {
        return (
            _msg.toUint64(1),
            _msg.toBytes16(9),
            _msg.toAddress(25),
            _msg.toUint128(57),
            _msg.toUint128(73),
            _msg.toUint128(89)
        );
    }

    function parseExecutedCollectInvest(bytes memory _msg)
        internal
        pure
        returns (
            uint64 poolId,
            bytes16 trancheId,
            address investor,
            uint128 currencyId,
            uint128 currencyPayout,
            uint128 trancheTokensPayout,
            uint128 remainingInvestOrder
        )
    {
        return (
            _msg.toUint64(1),
            _msg.toBytes16(9),
            _msg.toAddress(25),
            _msg.toUint128(57),
            _msg.toUint128(73),
            _msg.toUint128(89),
            _msg.toUint128(105)
        );
    }

    function parseExecutedCollectRedeem(bytes memory _msg)
        internal
        pure
        returns (
            uint64 poolId,
            bytes16 trancheId,
            address investor,
            uint128 currencyId,
            uint128 currencyPayout,
            uint128 trancheTokensPayout,
            uint128 remainingRedeemOrder
        )
    {
        return (
            _msg.toUint64(1),
            _msg.toBytes16(9),
            _msg.toAddress(25),
            _msg.toUint128(57),
            _msg.toUint128(73),
            _msg.toUint128(89),
            _msg.toUint128(105)
        );
    }

    function parseScheduleUpgrade(bytes memory _msg) internal pure returns (address _contract) {
        return (_msg.toAddress(1));
    }

    function parseCancelUpgrade(bytes memory _msg) internal pure returns (address _contract) {
        return (_msg.toAddress(1));
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
        return (
            _msg.toUint64(1), _msg.toBytes16(9), _msg.slice(25, 128).bytes128ToString(), _msg.toBytes32(153).toString()
        );
    }

    function parseCancelInvestOrder(bytes memory _msg)
        internal
        pure
        returns (uint64 poolId, bytes16 trancheId, address investor, uint128 currency)
    {
        return (_msg.toUint64(1), _msg.toBytes16(9), _msg.toAddress(25), _msg.toUint128(57));
    }

    function parseCancelRedeemOrder(bytes memory _msg)
        internal
        pure
        returns (uint64 poolId, bytes16 trancheId, address investor, uint128 currency)
    {
        return (_msg.toUint64(1), _msg.toBytes16(9), _msg.toAddress(25), _msg.toUint128(57));
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
        return (_msg.toUint64(1), _msg.toUint128(9));
    }

    /**
     * 0: call type (uint8 = 1 byte)
     * 1-8: poolId (uint64 = 8 bytes)
     * 9-24: trancheId (16 bytes)
     * 25-45: user (Ethereum address, 20 bytes - Skip 12 bytes from 32-byte addresses)
     *
     */
    function parseFreeze(bytes memory _msg) internal pure returns (uint64 poolId, bytes16 trancheId, address user) {
        return (_msg.toUint64(1), _msg.toBytes16(9), _msg.toAddress(25));
    }

    /**
     * 0: call type (uint8 = 1 byte)
     * 1-8: poolId (uint64 = 8 bytes)
     * 9-24: trancheId (16 bytes)
     * 25-45: user (Ethereum address, 20 bytes - Skip 12 bytes from 32-byte addresses)
     *
     */
    function parseUnfreeze(bytes memory _msg) internal pure returns (uint64 poolId, bytes16 trancheId, address user) {
        return (_msg.toUint64(1), _msg.toBytes16(9), _msg.toAddress(25));
    }

    /*
     * 0: call type (uint8 = 1 byte)
     * 1-8: poolId (uint64 = 8 bytes)
     * 9-24: trancheId (16 bytes)
     * 25-56: investor address (32 bytes)
     * 57-72: currency (uint128 = 16 bytes)
     * 73-89: amount (uint128 = 16 bytes)
     */
    function parseTriggerIncreaseRedeemOrder(bytes memory _msg)
        internal
        pure
        returns (uint64 poolId, bytes16 trancheId, address investor, uint128 currencyId, uint128 trancheTokenAmount)
    {
        return (_msg.toUint64(1), _msg.toBytes16(9), _msg.toAddress(25), _msg.toUint128(57), _msg.toUint128(73));
    }

    /**
     * 0: call type (uint8 = 1 byte)
     * 1-32: The keccak message proof (bytes32)
     */
    function parseMessageProof(bytes memory _msg) internal pure returns (bytes32 proof) {
        return (_msg.toBytes32(1));
    }

    /**
     * Initiate Message Recovery
     *
     * 0: call type (uint8 = 1 byte)
     * 1-32: The message hash (32 bytes)
     * 33-52: The router address (32 bytes)
     */
    function parseInitiateMessageRecovery(bytes memory _msg)
        internal
        pure
        returns (bytes32 messageHash, address router)
    {
        return (_msg.toBytes32(1), _msg.toAddress(33));
    }

    /**
     * Dispute Message Recovery
     *
     * 0: call type (uint8 = 1 byte)
     * 1-32: Message hash (32 bytes)
     */
    function parseDisputeMessageRecovery(bytes memory _msg) internal pure returns (bytes32 messageHash) {
        return (_msg.toBytes32(1));
    }

    /**
     * Recover Tokens sent to the wrong contract
     *
     * 0: call type (uint8 = 1 byte)
     * 1-32: The contract address (address = 32 bytes)
     * 33-64: The token address (address = 32 bytes)
     * 65-96: The recipient address (address = 32 bytes)
     * 97-128: The amount (uint256 = 32 bytes)
     */
    function parseRecoverTokens(bytes memory _msg)
        internal
        pure
        returns (address target, address token, address to, uint256 amount)
    {
        return (_msg.toAddress(1), _msg.toAddress(33), _msg.toAddress(65), _msg.toUint256(97));
    }

    function isRecoveryMessage(bytes memory _msg) internal pure returns (bool) {
        return messageType(_msg) == Call.InitiateMessageRecovery || messageType(_msg) == Call.DisputeMessageRecovery;
    }

    /**
     * Message Proof
     *
     * 0: call type (uint8 = 1 byte)
     * 1-32: The keccak message proof (bytes32)
     */
    function formatMessageProof(bytes memory message) internal pure returns (bytes memory) {
        return abi.encodePacked(uint8(Call.MessageProof), keccak256(message));
    }

    function formatMessageProof(bytes32 messageHash) internal pure returns (bytes memory) {
        return abi.encodePacked(uint8(Call.MessageProof), messageHash);
    }

    function isMessageProof(bytes memory _msg) internal pure returns (bool) {
        return messageType(_msg) == Call.MessageProof;
    }

    // Utils
    function formatDomain(Domain domain) internal pure returns (bytes9) {
        return bytes9(bytes1(uint8(domain)));
    }

    function formatDomain(Domain domain, uint64 chainId) internal pure returns (bytes9) {
        return bytes9(BytesLib.slice(abi.encodePacked(uint8(domain), chainId), 0, 9));
    }
}
