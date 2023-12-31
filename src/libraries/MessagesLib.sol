// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import {BytesLib} from "src/libraries/BytesLib.sol";

/// @title  MessagesLib
/// @dev    Library for encoding and decoding messages.
library MessagesLib {
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
        CollectInvest,
        /// 14 - Collect Redeem
        CollectRedeem,
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
        TriggerIncreaseRedeemOrder
    }

    enum Domain {
        Centrifuge,
        EVM
    }

    function messageType(bytes memory _msg) internal pure returns (Call _call) {
        _call = Call(BytesLib.toUint8(_msg, 0));
    }

    /**
     * Add Currency
     *
     * 0: call type (uint8 = 1 byte)
     * 1-16: The Liquidity Pool's global currency id (uint128 = 16 bytes)
     * 17-36: The EVM address of the currency (address = 20 bytes)
     */
    function formatAddCurrency(uint128 currency, address currencyAddress) internal pure returns (bytes memory) {
        return abi.encodePacked(uint8(Call.AddCurrency), currency, currencyAddress);
    }

    function parseAddCurrency(bytes memory _msg) internal pure returns (uint128 currency, address currencyAddress) {
        currency = BytesLib.toUint128(_msg, 1);
        currencyAddress = BytesLib.toAddress(_msg, 17);
    }

    /**
     * Add pool
     *
     * 0: call type (uint8 = 1 byte)
     * 1-8: poolId (uint64 = 8 bytes)
     */
    function formatAddPool(uint64 poolId) internal pure returns (bytes memory) {
        return abi.encodePacked(uint8(Call.AddPool), poolId);
    }

    function parseAddPool(bytes memory _msg) internal pure returns (uint64 poolId) {
        poolId = BytesLib.toUint64(_msg, 1);
    }

    /**
     * Allow Investment Currency
     *
     * 0: call type (uint8 = 1 byte)
     * 1-8: poolId (uint64 = 8 bytes)
     * 9-24: currency (uint128 = 16 bytes)
     */
    function formatAllowInvestmentCurrency(uint64 poolId, uint128 currency) internal pure returns (bytes memory) {
        return abi.encodePacked(uint8(Call.AllowInvestmentCurrency), poolId, currency);
    }

    function parseAllowInvestmentCurrency(bytes memory _msg) internal pure returns (uint64 poolId, uint128 currency) {
        poolId = BytesLib.toUint64(_msg, 1);
        currency = BytesLib.toUint128(_msg, 9);
    }

    /**
     * Add tranche
     *
     * 0: call type (uint8 = 1 byte)
     * 1-8: poolId (uint64 = 8 bytes)
     * 9-24: trancheId (16 bytes)
     * 25-152: tokenName (string = 128 bytes)
     * 153-184: tokenSymbol (string = 32 bytes)
     * 185: decimals (uint8 = 1 byte)
     * 186: restriction set (uint8 = 1 byte)
     */
    function formatAddTranche(
        uint64 poolId,
        bytes16 trancheId,
        string memory tokenName,
        string memory tokenSymbol,
        uint8 decimals,
        uint8 restrictionSet
    ) internal pure returns (bytes memory) {
        return abi.encodePacked(
            uint8(Call.AddTranche),
            poolId,
            trancheId,
            _stringToBytes128(tokenName),
            _stringToBytes32(tokenSymbol),
            decimals,
            restrictionSet
        );
    }

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
        poolId = BytesLib.toUint64(_msg, 1);
        trancheId = BytesLib.toBytes16(_msg, 9);
        tokenName = _bytes128ToString(BytesLib.slice(_msg, 25, 128));
        tokenSymbol = _bytes32ToString(BytesLib.toBytes32(_msg, 153));
        decimals = BytesLib.toUint8(_msg, 185);
        restrictionSet = 0;
        if (_msg.length > 186) {
            restrictionSet = BytesLib.toUint8(_msg, 186);
        }
    }

    /**
     * Update member
     *
     * 0: call type (uint8 = 1 byte)
     * 1-8: poolId (uint64 = 8 bytes)
     * 9-24: trancheId (16 bytes)
     * 25-45: user (Ethereum address, 20 bytes - Skip 12 bytes from 32-byte addresses)
     * 57-65: validUntil (uint64 = 8 bytes)
     *
     */
    function formatUpdateMember(uint64 poolId, bytes16 trancheId, address member, uint64 validUntil)
        internal
        pure
        returns (bytes memory)
    {
        return formatUpdateMember(poolId, trancheId, bytes32(bytes20(member)), validUntil);
    }

    function formatUpdateMember(uint64 poolId, bytes16 trancheId, bytes32 member, uint64 validUntil)
        internal
        pure
        returns (bytes memory)
    {
        return abi.encodePacked(uint8(Call.UpdateMember), poolId, trancheId, member, validUntil);
    }

    function parseUpdateMember(bytes memory _msg)
        internal
        pure
        returns (uint64 poolId, bytes16 trancheId, address user, uint64 validUntil)
    {
        poolId = BytesLib.toUint64(_msg, 1);
        trancheId = BytesLib.toBytes16(_msg, 9);
        user = BytesLib.toAddress(_msg, 25);
        validUntil = BytesLib.toUint64(_msg, 57);
    }

    /**
     * Update a Tranche token's price
     *
     * 0: call type (uint8 = 1 byte)
     * 1-8: poolId (uint64 = 8 bytes)
     * 9-24: trancheId (16 bytes)
     * 25-40: currency (uint128 = 16 bytes)
     * 41-56: price (uint128 = 16 bytes)
     * 57-64: computedAt (uint64 = 8 bytes)
     */
    function formatUpdateTrancheTokenPrice(
        uint64 poolId,
        bytes16 trancheId,
        uint128 currencyId,
        uint128 price,
        uint64 computedAt
    ) internal pure returns (bytes memory) {
        return abi.encodePacked(uint8(Call.UpdateTrancheTokenPrice), poolId, trancheId, currencyId, price, computedAt);
    }

    function parseUpdateTrancheTokenPrice(bytes memory _msg)
        internal
        pure
        returns (uint64 poolId, bytes16 trancheId, uint128 currencyId, uint128 price, uint64 computedAt)
    {
        poolId = BytesLib.toUint64(_msg, 1);
        trancheId = BytesLib.toBytes16(_msg, 9);
        currencyId = BytesLib.toUint128(_msg, 25);
        price = BytesLib.toUint128(_msg, 41);
        computedAt = BytesLib.toUint64(_msg, 57);
    }

    /*
     * Transfer Message - Transfer stable coins
     *
     * 0: call type (uint8 = 1 byte)
     * 1-16: currency (uint128 = 16 bytes)
     * 17-48: sender address (32 bytes)
     * 49-80: receiver address (32 bytes)
     * 81-96: amount (uint128 = 16 bytes)
     */
    function formatTransfer(uint128 currency, bytes32 sender, bytes32 receiver, uint128 amount)
        internal
        pure
        returns (bytes memory)
    {
        return abi.encodePacked(uint8(Call.Transfer), currency, sender, receiver, amount);
    }

    function parseTransfer(bytes memory _msg)
        internal
        pure
        returns (uint128 currency, bytes32 sender, bytes32 receiver, uint128 amount)
    {
        currency = BytesLib.toUint128(_msg, 1);
        sender = BytesLib.toBytes32(_msg, 17);
        receiver = BytesLib.toBytes32(_msg, 49);
        amount = BytesLib.toUint128(_msg, 81);
    }

    // An optimised `parseTransfer` function that saves gas by ignoring the `sender` field and that
    // parses and returns the `recipient` as an `address` instead of the `bytes32` the message holds.
    function parseIncomingTransfer(bytes memory _msg)
        internal
        pure
        returns (uint128 currency, address recipient, uint128 amount)
    {
        currency = BytesLib.toUint128(_msg, 1);
        recipient = BytesLib.toAddress(_msg, 49);
        amount = BytesLib.toUint128(_msg, 81);
    }

    /**
     * TransferTrancheTokens
     *
     * 0: call type (uint8 = 1 byte)
     * 1-8: poolId (uint64 = 8 bytes)
     * 9-24: trancheId (16 bytes)
     * 25-56: sender (bytes32)
     * 57-65: destinationDomain ((Domain: u8, ChainId: u64) =  9 bytes total)
     * 66-97: destinationAddress (32 bytes - Either a Centrifuge address or an EVM address followed by 12 zeros)
     * 98-113: amount (uint128 = 16 bytes)
     */
    function formatTransferTrancheTokens(
        uint64 poolId,
        bytes16 trancheId,
        bytes32 sender,
        bytes9 destinationDomain,
        bytes32 destinationAddress,
        uint128 amount
    ) internal pure returns (bytes memory) {
        return abi.encodePacked(
            uint8(Call.TransferTrancheTokens), poolId, trancheId, sender, destinationDomain, destinationAddress, amount
        );
    }

    // Overload: Format a TransferTrancheTokens to an EVM domain
    // Note: This is an overload function to dry the cast from `address` to `bytes32`
    // for the `destinationAddress` field by using the default `formatTransferTrancheTokens` implementation
    // by appending 12 zeros to the evm-based `destinationAddress`.
    function formatTransferTrancheTokens(
        uint64 poolId,
        bytes16 trancheId,
        bytes32 sender,
        bytes9 destinationDomain,
        address destinationAddress,
        uint128 amount
    ) internal pure returns (bytes memory) {
        return formatTransferTrancheTokens(
            poolId, trancheId, sender, destinationDomain, bytes32(bytes20(destinationAddress)), amount
        );
    }

    // Parse a TransferTrancheTokens to an EVM-based `destinationAddress` (20-byte long).
    // We ignore the `sender` and the `domain` since it's not relevant when parsing an incoming message.
    function parseTransferTrancheTokens20(bytes memory _msg)
        internal
        pure
        returns (uint64 poolId, bytes16 trancheId, address destinationAddress, uint128 amount)
    {
        poolId = BytesLib.toUint64(_msg, 1);
        trancheId = BytesLib.toBytes16(_msg, 9);
        // ignore: `sender` at bytes 25-56
        // ignore: `domain` at bytes 57-65
        destinationAddress = BytesLib.toAddress(_msg, 66);
        amount = BytesLib.toUint128(_msg, 98);
    }

    /*
     * IncreaseInvestOrder Message
     *
     * 0: call type (uint8 = 1 byte)
     * 1-8: poolId (uint64 = 8 bytes)
     * 9-24: trancheId (16 bytes)
     * 25-56: investor address (32 bytes)
     * 57-72: currency (uint128 = 16 bytes)
     * 73-89: amount (uint128 = 16 bytes)
     */
    function formatIncreaseInvestOrder(
        uint64 poolId,
        bytes16 trancheId,
        bytes32 investor,
        uint128 currency,
        uint128 amount
    ) internal pure returns (bytes memory) {
        return abi.encodePacked(uint8(Call.IncreaseInvestOrder), poolId, trancheId, investor, currency, amount);
    }

    function parseIncreaseInvestOrder(bytes memory _msg)
        internal
        pure
        returns (uint64 poolId, bytes16 trancheId, bytes32 investor, uint128 currency, uint128 amount)
    {
        poolId = BytesLib.toUint64(_msg, 1);
        trancheId = BytesLib.toBytes16(_msg, 9);
        investor = BytesLib.toBytes32(_msg, 25);
        currency = BytesLib.toUint128(_msg, 57);
        amount = BytesLib.toUint128(_msg, 73);
    }

    /*
     * DecreaseInvestOrder Message
     *
     * 0: call type (uint8 = 1 byte)
     * 1-8: poolId (uint64 = 8 bytes)
     * 9-24: trancheId (16 bytes)
     * 25-56: investor address (32 bytes)
     * 57-72: currency (uint128 = 16 bytes)
     * 73-89: amount (uint128 = 16 bytes)
     */
    function formatDecreaseInvestOrder(
        uint64 poolId,
        bytes16 trancheId,
        bytes32 investor,
        uint128 currency,
        uint128 amount
    ) internal pure returns (bytes memory) {
        return abi.encodePacked(uint8(Call.DecreaseInvestOrder), poolId, trancheId, investor, currency, amount);
    }

    function parseDecreaseInvestOrder(bytes memory _msg)
        internal
        pure
        returns (uint64 poolId, bytes16 trancheId, bytes32 investor, uint128 currency, uint128 amount)
    {
        return parseIncreaseInvestOrder(_msg);
    }

    /*
     * IncreaseRedeemOrder Message
     *
     * 0: call type (uint8 = 1 byte)
     * 1-8: poolId (uint64 = 8 bytes)
     * 9-24: trancheId (16 bytes)
     * 25-56: investor address (32 bytes)
     * 57-72: currency (uint128 = 16 bytes)
     * 73-89: amount (uint128 = 16 bytes)
     */
    function formatIncreaseRedeemOrder(
        uint64 poolId,
        bytes16 trancheId,
        bytes32 investor,
        uint128 currency,
        uint128 amount
    ) internal pure returns (bytes memory) {
        return abi.encodePacked(uint8(Call.IncreaseRedeemOrder), poolId, trancheId, investor, currency, amount);
    }

    function parseIncreaseRedeemOrder(bytes memory _msg)
        internal
        pure
        returns (uint64 poolId, bytes16 trancheId, bytes32 investor, uint128 currency, uint128 amount)
    {
        return parseIncreaseInvestOrder(_msg);
    }

    /*
     * DecreaseRedeemOrder Message
     *
     * 0: call type (uint8 = 1 byte)
     * 1-8: poolId (uint64 = 8 bytes)
     * 9-24: trancheId (16 bytes)
     * 25-56: investor address (32 bytes)
     * 57-72: currency (uint128 = 16 bytes)
     * 73-89: amount (uint128 = 16 bytes)
     */
    function formatDecreaseRedeemOrder(
        uint64 poolId,
        bytes16 trancheId,
        bytes32 investor,
        uint128 currency,
        uint128 amount
    ) internal pure returns (bytes memory) {
        return abi.encodePacked(uint8(Call.DecreaseRedeemOrder), poolId, trancheId, investor, currency, amount);
    }

    function parseDecreaseRedeemOrder(bytes memory _msg)
        internal
        pure
        returns (uint64 poolId, bytes16 trancheId, bytes32 investor, uint128 currency, uint128 amount)
    {
        return parseDecreaseInvestOrder(_msg);
    }

    /*
     * CollectInvest Message
     *
     * 0: call type (uint8 = 1 byte)
     * 1-8: poolId (uint64 = 8 bytes)
     * 9-24: trancheId (16 bytes)
     * 25-56: investor address (32 bytes)
     */
    function formatCollectInvest(uint64 poolId, bytes16 trancheId, bytes32 investor, uint128 currency)
        internal
        pure
        returns (bytes memory)
    {
        return abi.encodePacked(uint8(Call.CollectInvest), poolId, trancheId, investor, currency);
    }

    function parseCollectInvest(bytes memory _msg)
        internal
        pure
        returns (uint64 poolId, bytes16 trancheId, bytes32 investor, uint128 currency)
    {
        poolId = BytesLib.toUint64(_msg, 1);
        trancheId = BytesLib.toBytes16(_msg, 9);
        investor = BytesLib.toBytes32(_msg, 25);
        currency = BytesLib.toUint128(_msg, 57);
    }

    /*
     * CollectRedeem Message
     *
     * 0: call type (uint8 = 1 byte)
     * 1-8: poolId (uint64 = 8 bytes)
     * 9-24: trancheId (16 bytes)
     * 25-56: investor address (32 bytes)
     */
    function formatCollectRedeem(uint64 poolId, bytes16 trancheId, bytes32 investor, uint128 currency)
        internal
        pure
        returns (bytes memory)
    {
        return abi.encodePacked(uint8(Call.CollectRedeem), poolId, trancheId, investor, currency);
    }

    function parseCollectRedeem(bytes memory _msg)
        internal
        pure
        returns (uint64 poolId, bytes16 trancheId, bytes32 investor, uint128 currency)
    {
        poolId = BytesLib.toUint64(_msg, 1);
        trancheId = BytesLib.toBytes16(_msg, 9);
        investor = BytesLib.toBytes32(_msg, 25);
        currency = BytesLib.toUint128(_msg, 57);
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
        poolId = BytesLib.toUint64(_msg, 1);
        trancheId = BytesLib.toBytes16(_msg, 9);
        investor = BytesLib.toAddress(_msg, 25);
        currency = BytesLib.toUint128(_msg, 57);
        trancheTokenPayout = BytesLib.toUint128(_msg, 73);
        remainingInvestOrder = BytesLib.toUint128(_msg, 89);
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
        poolId = BytesLib.toUint64(_msg, 1);
        trancheId = BytesLib.toBytes16(_msg, 9);
        investor = BytesLib.toAddress(_msg, 25);
        currency = BytesLib.toUint128(_msg, 57);
        trancheTokensPayout = BytesLib.toUint128(_msg, 73);
        remainingRedeemOrder = BytesLib.toUint128(_msg, 89);
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
        poolId = BytesLib.toUint64(_msg, 1);
        trancheId = BytesLib.toBytes16(_msg, 9);
        investor = BytesLib.toAddress(_msg, 25);
        currency = BytesLib.toUint128(_msg, 57);
        currencyPayout = BytesLib.toUint128(_msg, 73);
        trancheTokensPayout = BytesLib.toUint128(_msg, 89);
        remainingInvestOrder = BytesLib.toUint128(_msg, 105);
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
        poolId = BytesLib.toUint64(_msg, 1);
        trancheId = BytesLib.toBytes16(_msg, 9);
        investor = BytesLib.toAddress(_msg, 25);
        currency = BytesLib.toUint128(_msg, 57);
        currencyPayout = BytesLib.toUint128(_msg, 73);
        trancheTokensPayout = BytesLib.toUint128(_msg, 89);
        remainingRedeemOrder = BytesLib.toUint128(_msg, 105);
    }

    function formatScheduleUpgrade(address _contract) internal pure returns (bytes memory) {
        return abi.encodePacked(uint8(Call.ScheduleUpgrade), _contract);
    }

    function parseScheduleUpgrade(bytes memory _msg) internal pure returns (address _contract) {
        _contract = BytesLib.toAddress(_msg, 1);
    }

    function formatCancelUpgrade(address _contract) internal pure returns (bytes memory) {
        return abi.encodePacked(uint8(Call.CancelUpgrade), _contract);
    }

    function parseCancelUpgrade(bytes memory _msg) internal pure returns (address _contract) {
        _contract = BytesLib.toAddress(_msg, 1);
    }

    /**
     * Update tranche token metadata
     *
     * 0: call type (uint8 = 1 byte)
     * 1-8: poolId (uint64 = 8 bytes)
     * 9-24: trancheId (16 bytes)
     * 25-152: tokenName (string = 128 bytes)
     * 153-184: tokenSymbol (string = 32 bytes)
     */
    function formatUpdateTrancheTokenMetadata(
        uint64 poolId,
        bytes16 trancheId,
        string memory tokenName,
        string memory tokenSymbol
    ) internal pure returns (bytes memory) {
        return abi.encodePacked(
            uint8(Call.UpdateTrancheTokenMetadata),
            poolId,
            trancheId,
            _stringToBytes128(tokenName),
            _stringToBytes32(tokenSymbol)
        );
    }

    function parseUpdateTrancheTokenMetadata(bytes memory _msg)
        internal
        pure
        returns (uint64 poolId, bytes16 trancheId, string memory tokenName, string memory tokenSymbol)
    {
        poolId = BytesLib.toUint64(_msg, 1);
        trancheId = BytesLib.toBytes16(_msg, 9);
        tokenName = _bytes128ToString(BytesLib.slice(_msg, 25, 128));
        tokenSymbol = _bytes32ToString(BytesLib.toBytes32(_msg, 153));
    }

    function formatCancelInvestOrder(uint64 poolId, bytes16 trancheId, bytes32 investor, uint128 currency)
        internal
        pure
        returns (bytes memory)
    {
        return abi.encodePacked(uint8(Call.CancelInvestOrder), poolId, trancheId, investor, currency);
    }

    function parseCancelInvestOrder(bytes memory _msg)
        internal
        pure
        returns (uint64 poolId, bytes16 trancheId, address investor, uint128 currency)
    {
        poolId = BytesLib.toUint64(_msg, 1);
        trancheId = BytesLib.toBytes16(_msg, 9);
        investor = BytesLib.toAddress(_msg, 25);
        currency = BytesLib.toUint128(_msg, 57);
    }

    function formatCancelRedeemOrder(uint64 poolId, bytes16 trancheId, bytes32 investor, uint128 currency)
        internal
        pure
        returns (bytes memory)
    {
        return abi.encodePacked(uint8(Call.CancelRedeemOrder), poolId, trancheId, investor, currency);
    }

    function parseCancelRedeemOrder(bytes memory _msg)
        internal
        pure
        returns (uint64 poolId, bytes16 trancheId, address investor, uint128 currency)
    {
        poolId = BytesLib.toUint64(_msg, 1);
        trancheId = BytesLib.toBytes16(_msg, 9);
        investor = BytesLib.toAddress(_msg, 25);
        currency = BytesLib.toUint128(_msg, 57);
    }

    /**
     * Disallow Investment Currency
     *
     * 0: call type (uint8 = 1 byte)
     * 1-8: poolId (uint64 = 8 bytes)
     * 9-24: currency (uint128 = 16 bytes)
     */
    function formatDisallowInvestmentCurrency(uint64 poolId, uint128 currency) internal pure returns (bytes memory) {
        return abi.encodePacked(uint8(Call.DisallowInvestmentCurrency), poolId, currency);
    }

    function parseDisallowInvestmentCurrency(bytes memory _msg)
        internal
        pure
        returns (uint64 poolId, uint128 currency)
    {
        poolId = BytesLib.toUint64(_msg, 1);
        currency = BytesLib.toUint128(_msg, 9);
    }

    /**
     * Freeze
     *
     * 0: call type (uint8 = 1 byte)
     * 1-8: poolId (uint64 = 8 bytes)
     * 9-24: trancheId (16 bytes)
     * 25-45: user (Ethereum address, 20 bytes - Skip 12 bytes from 32-byte addresses)
     *
     */
    function formatFreeze(uint64 poolId, bytes16 trancheId, address member) internal pure returns (bytes memory) {
        return abi.encodePacked(uint8(Call.Freeze), poolId, trancheId, bytes32(bytes20(member)));
    }

    function parseFreeze(bytes memory _msg) internal pure returns (uint64 poolId, bytes16 trancheId, address user) {
        poolId = BytesLib.toUint64(_msg, 1);
        trancheId = BytesLib.toBytes16(_msg, 9);
        user = BytesLib.toAddress(_msg, 25);
    }

    /**
     * Unfreeze
     *
     * 0: call type (uint8 = 1 byte)
     * 1-8: poolId (uint64 = 8 bytes)
     * 9-24: trancheId (16 bytes)
     * 25-45: user (Ethereum address, 20 bytes - Skip 12 bytes from 32-byte addresses)
     *
     */
    function formatUnfreeze(uint64 poolId, bytes16 trancheId, address user) internal pure returns (bytes memory) {
        return abi.encodePacked(uint8(Call.Unfreeze), poolId, trancheId, bytes32(bytes20(user)));
    }

    function parseUnfreeze(bytes memory _msg) internal pure returns (uint64 poolId, bytes16 trancheId, address user) {
        poolId = BytesLib.toUint64(_msg, 1);
        trancheId = BytesLib.toBytes16(_msg, 9);
        user = BytesLib.toAddress(_msg, 25);
    }

    /*
     * TriggerIncreaseRedeemOrder Message
     *
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
        poolId = BytesLib.toUint64(_msg, 1);
        trancheId = BytesLib.toBytes16(_msg, 9);
        investor = BytesLib.toAddress(_msg, 25);
        currency = BytesLib.toUint128(_msg, 57);
        trancheTokenAmount = BytesLib.toUint128(_msg, 73);
    }

    // Utils
    function formatDomain(Domain domain) public pure returns (bytes9) {
        return bytes9(bytes1(uint8(domain)));
    }

    function formatDomain(Domain domain, uint64 chainId) public pure returns (bytes9) {
        return bytes9(BytesLib.slice(abi.encodePacked(uint8(domain), chainId), 0, 9));
    }

    function _stringToBytes128(string memory source) internal pure returns (bytes memory) {
        bytes memory temp = bytes(source);
        bytes memory result = new bytes(128);

        for (uint256 i = 0; i < 128; i++) {
            if (i < temp.length) {
                result[i] = temp[i];
            } else {
                result[i] = 0x00;
            }
        }

        return result;
    }

    function _bytes128ToString(bytes memory _bytes128) internal pure returns (string memory) {
        require(_bytes128.length == 128, "Input should be 128 bytes");

        uint8 i = 0;
        while (i < 128 && _bytes128[i] != 0) {
            i++;
        }

        bytes memory bytesArray = new bytes(i);

        for (uint8 j = 0; j < i; j++) {
            bytesArray[j] = _bytes128[j];
        }

        return string(bytesArray);
    }

    function _stringToBytes32(string memory source) internal pure returns (bytes32 result) {
        bytes memory tempEmptyStringTest = bytes(source);
        if (tempEmptyStringTest.length == 0) {
            return 0x0;
        }

        assembly {
            result := mload(add(source, 32))
        }
    }

    function _bytes32ToString(bytes32 _bytes32) internal pure returns (string memory) {
        uint8 i = 0;
        while (i < 32 && _bytes32[i] != 0) {
            i++;
        }
        bytes memory bytesArray = new bytes(i);
        for (i = 0; i < 32 && _bytes32[i] != 0; i++) {
            bytesArray[i] = _bytes32[i];
        }
        return string(bytesArray);
    }
}
