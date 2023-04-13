// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.18;

import "memview-sol/TypedMemView.sol";

library ConnectorMessages {
    using TypedMemView for bytes;
    using TypedMemView for bytes29;

    enum Call
    /// 0 - An invalid message
    {
        Invalid,
        /// 1 - Add a currency id -> EVM address mapping
        AddCurrency,
        /// 2 - Add Pool
        AddPool,
        /// 3 - Allow a registered currency to be used as a pool currency or as an investment currency
        AllowPoolCurrency,
        /// 4 - Add a Pool's Tranche Token
        AddTranche,
        /// 5 - Update the price of a Tranche Token
        UpdateTrancheTokenPrice,
        /// 6 - Update the member list of a tranche token with a new member
        UpdateMember,
        /// 7 - A transfer of Stable Coins
        Transfer,
        /// 8 - A transfer of Tranche tokens
        TransferTrancheTokens,
        /// 9 - Increase an investment order by a given amount
        IncreaseInvestOrder,
        /// 10 - Decrease an investment order by a given amount
        DecreaseInvestOrder,
        /// 11 - Increase a Redeem order by a given amount
        IncreaseRedeemOrder,
        /// 12 - Decrease a Redeem order by a given amount
        DecreaseRedeemOrder,
        /// 13 - Collect Redeem
        CollectRedeem,
        /// 14 - Collect for another user
        CollectForRedeem,
        /// 15 - Collect investment
        CollectInvest,
        /// 16 - Collect investment for another user
        CollectForInvest
    }

    enum Domain {
        Centrifuge,
        EVM
    }

    function messageType(bytes29 _msg) internal pure returns (Call _call) {
        _call = Call(uint8(_msg.indexUint(0, 1)));
    }

    /**
     * Add Currency
     *
     * 0: call type (uint8 = 1 byte)
     * 1-16: The Connector's global currency id (uint128 = 16 bytes)
     * 17-36: The EVM address of the currency (address = 20 bytes)
     */
    function formatAddCurrency(uint128 currency, address currencyAddress) internal pure returns (bytes memory) {
        return abi.encodePacked(uint8(Call.AddCurrency), currency, currencyAddress);
    }

    function isAddCurrency(bytes29 _msg) internal pure returns (bool) {
        return messageType(_msg) == Call.AddCurrency;
    }

    function parseAddCurrency(bytes29 _msg) internal pure returns (uint128 currency, address currencyAddress) {
        currency = uint128(_msg.indexUint(1, 16));
        currencyAddress = address(bytes20(_msg.index(17, 20)));
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

    function isAddPool(bytes29 _msg) internal pure returns (bool) {
        return messageType(_msg) == Call.AddPool;
    }

    function parseAddPool(bytes29 _msg) internal pure returns (uint64 poolId) {
        poolId = uint64(_msg.indexUint(1, 8));
    }

    /**
     * Allow Pool Currency
     *
     * 0: call type (uint8 = 1 byte)
     * 1-16: currency (uint128 = 16 bytes)
     */
    function formatAllowPoolCurrency(uint128 currency) internal pure returns (bytes memory) {
        return abi.encodePacked(uint8(Call.AllowPoolCurrency), currency);
    }

    function isAllowPoolCurrency(bytes29 _msg) internal pure returns (bool) {
        return messageType(_msg) == Call.AllowPoolCurrency;
    }

    function parseAllowPoolCurrency(bytes29 _msg) internal pure returns (uint128 currency) {
        currency = uint128(_msg.indexUint(1, 16));
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
     * 186-202: price (uint128 = 16 bytes)
     */
    function formatAddTranche(
        uint64 poolId,
        bytes16 trancheId,
        string memory tokenName,
        string memory tokenSymbol,
        uint8 decimals,
        uint128 price
    ) internal pure returns (bytes memory) {
        // TODO(nuno): Now, we encode `tokenName` as a 128-bytearray by first encoding `tokenName`
        // to bytes32 and then we encode three empty bytes32's, which sum up to a total of 128 bytes.
        // Add support to actually encode `tokenName` fully as a 128 bytes string.
        return abi.encodePacked(
            uint8(Call.AddTranche),
            poolId,
            trancheId,
            stringToBytes32(tokenName),
            bytes32(""),
            bytes32(""),
            bytes32(""),
            stringToBytes32(tokenSymbol),
            decimals,
            price
        );
    }

    function isAddTranche(bytes29 _msg) internal pure returns (bool) {
        return messageType(_msg) == Call.AddTranche;
    }

    function parseAddTranche(bytes29 _msg)
        internal
        pure
        returns (
            uint64 poolId,
            bytes16 trancheId,
            string memory tokenName,
            string memory tokenSymbol,
            uint8 decimals,
            uint128 price
        )
    {
        poolId = uint64(_msg.indexUint(1, 8));
        trancheId = bytes16(_msg.index(9, 16));
        tokenName = bytes32ToString(bytes32(_msg.index(25, 32)));
        tokenSymbol = bytes32ToString(bytes32(_msg.index(153, 32)));
        decimals = uint8(_msg.indexUint(185, 1));
        price = uint128(_msg.indexUint(186, 16));
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
     * TODO: use bytes32 for user (for non-EVM compatibility)
     */
    function formatUpdateMember(uint64 poolId, bytes16 trancheId, address user, uint64 validUntil)
        internal
        pure
        returns (bytes memory)
    {
        // NOTE: Since parseUpdateMember parses the first 20 bytes of `user` and skips the following 12
        // here we need to append 12 zeros to make it right. Drop once we support 32-byte addresses.
        return abi.encodePacked(
            uint8(Call.UpdateMember), poolId, trancheId, user, bytes(hex"000000000000000000000000"), validUntil
        );
    }

    function isUpdateMember(bytes29 _msg) internal pure returns (bool) {
        return messageType(_msg) == Call.UpdateMember;
    }

    function parseUpdateMember(bytes29 _msg)
        internal
        pure
        returns (uint64 poolId, bytes16 trancheId, address user, uint64 validUntil)
    {
        poolId = uint64(_msg.indexUint(1, 8));
        trancheId = bytes16(_msg.index(9, 16));
        user = address(bytes20(_msg.index(25, 20)));
        validUntil = uint64(_msg.indexUint(57, 8));
    }

    /**
     * Update a Tranche token's price
     *
     * 0: call type (uint8 = 1 byte)
     * 1-8: poolId (uint64 = 8 bytes)
     * 9-24: trancheId (16 bytes)
     * 25-41: price (uint128 = 16 bytes)
     */
    function formatUpdateTrancheTokenPrice(uint64 poolId, bytes16 trancheId, uint128 price)
        internal
        pure
        returns (bytes memory)
    {
        return abi.encodePacked(uint8(Call.UpdateTrancheTokenPrice), poolId, trancheId, price);
    }

    function isUpdateTrancheTokenPrice(bytes29 _msg) internal pure returns (bool) {
        return messageType(_msg) == Call.UpdateTrancheTokenPrice;
    }

    function parseUpdateTrancheTokenPrice(bytes29 _msg)
        internal
        pure
        returns (uint64 poolId, bytes16 trancheId, uint128 price)
    {
        poolId = uint64(_msg.indexUint(1, 8));
        trancheId = bytes16(_msg.index(9, 16));
        price = uint128(_msg.indexUint(25, 16));
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
    // todo(nuno): we probably need to include the domain
    function formatTransfer(uint128 currency, bytes32 sender, bytes32 receiver, uint128 amount)
        internal
        pure
        returns (bytes memory)
    {
        return abi.encodePacked(uint8(Call.Transfer), currency, sender, receiver, amount);
    }

    function isTransfer(bytes29 _msg) internal pure returns (bool) {
        return messageType(_msg) == Call.Transfer;
    }

    function parseTransfer(bytes29 _msg)
        internal
        pure
        returns (uint128 currency, bytes32 sender, bytes32 receiver, uint128 amount)
    {
        currency = uint128(_msg.indexUint(1, 16));
        sender = bytes32(_msg.index(17, 32));
        receiver = bytes32(_msg.index(49, 32));
        amount = uint128(_msg.indexUint(81, 16));
    }

    /**
     * TransferTrancheTokens
     *
     * 0: call type (uint8 = 1 byte)
     * 1-8: poolId (uint64 = 8 bytes)
     * 9-24: trancheId (16 bytes)
     * 25-33: destinationDomain (Domain = 9 bytes)
     * 34-65: destinationChainId (uint256 = 32 bytes)
     * 66-73: destinationAddress (32 bytes - Either a Centrifuge chain address or an EVM address followed by 12 zeros)
     * 74-89: amount (uint128 = 16 bytes)
     */
    function formatTransferTrancheTokens(
        uint64 poolId,
        bytes16 trancheId,
        bytes9 destinationDomain,
        uint256 destinationChainId,
        bytes32 destinationAddress,
        uint128 amount
    ) internal pure returns (bytes memory) {
        return abi.encodePacked(
            uint8(Call.TransferTrancheTokens),
            poolId,
            trancheId,
            destinationDomain,
            destinationChainId,
            destinationAddress,
            amount
        );
    }

    // Format a TransferTrancheTokens to an EVM domain
    // Note: This is an overload function to dry the cast from `address` to `bytes32`
    // for the `destinationAddress` field by using the default `formatTransferTrancheTokens` implementation
    // by appending 12 zeros to the evm-based `destinationAddress`.
    function formatTransferTrancheTokens(
        uint64 poolId,
        bytes16 trancheId,
        bytes9 destinationDomain,
        uint256 destinationChainId,
        address destinationAddress,
        uint128 amount
    ) internal pure returns (bytes memory) {
        return formatTransferTrancheTokens(
            poolId, trancheId, destinationDomain, destinationChainId, bytes32(bytes20(destinationAddress)), amount
        );
    }

    function isTransferTrancheTokens(bytes29 _msg) internal pure returns (bool) {
        return messageType(_msg) == Call.TransferTrancheTokens;
    }

    // Parse a TransferTrancheTokens to a Centrifuge-based `destinationAddress` (32-byte long)
    function parseTransferTrancheTokens32(bytes29 _msg)
        internal
        pure
        returns (
            uint64 poolId,
            bytes16 trancheId,
            bytes9 encodedDomain,
            uint256 destinationChainId,
            bytes32 destinationAddress,
            uint128 amount
        )
    {
        poolId = uint64(_msg.indexUint(1, 8));
        trancheId = bytes16(_msg.index(9, 16));
        encodedDomain = bytes9(_msg.index(25, 9));
        destinationChainId = uint256(_msg.indexUint(34, 32));
        destinationAddress = bytes32(_msg.index(66, 32));
        amount = uint128(_msg.indexUint(98, 16));
    }

    // Parse a TransferTrancheTokens to an EVM-based `destinationAddress` (20-byte long)
    function parseTransferTrancheTokens20(bytes29 _msg)
        internal
        pure
        returns (
            uint64 poolId,
            bytes16 trancheId,
            bytes9 encodedDomain,
            uint256 destinationChainId,
            address destinationAddress,
            uint128 amount
        )
    {
        (
            uint64 poolId_,
            bytes16 trancheId_,
            bytes9 encodedDomain_,
            uint256 destinationChainId_,
            bytes32 destinationAddress32_,
            uint128 amount_
        ) = parseTransferTrancheTokens32(_msg);
        destinationAddress = address(bytes20(destinationAddress32_));
        return (poolId_, trancheId_, encodedDomain_, destinationChainId_, destinationAddress, amount_);
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

    function isIncreaseInvestOrder(bytes29 _msg) internal pure returns (bool) {
        return messageType(_msg) == Call.IncreaseInvestOrder;
    }

    function parseIncreaseInvestOrder(bytes29 _msg)
        internal
        pure
        returns (uint64 poolId, bytes16 trancheId, bytes32 investor, uint128 currency, uint128 amount)
    {
        poolId = uint64(_msg.indexUint(1, 8));
        trancheId = bytes16(_msg.index(9, 16));
        investor = bytes32(_msg.index(25, 32));
        currency = uint128(_msg.indexUint(57, 16));
        amount = uint128(_msg.indexUint(73, 16));
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

    function isDecreaseInvestOrder(bytes29 _msg) internal pure returns (bool) {
        return messageType(_msg) == Call.DecreaseInvestOrder;
    }

    function parseDecreaseInvestOrder(bytes29 _msg)
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

    function isIncreaseRedeemOrder(bytes29 _msg) internal pure returns (bool) {
        return messageType(_msg) == Call.IncreaseRedeemOrder;
    }

    function parseIncreaseRedeemOrder(bytes29 _msg)
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

    function isDecreaseRedeemOrder(bytes29 _msg) internal pure returns (bool) {
        return messageType(_msg) == Call.DecreaseRedeemOrder;
    }

    function parseDecreaseRedeemOrder(bytes29 _msg)
        internal
        pure
        returns (uint64 poolId, bytes16 trancheId, bytes32 investor, uint128 currency, uint128 amount)
    {
        return parseDecreaseInvestOrder(_msg);
    }

    /*
     * CollectRedeem Message
     *
     * 0: call type (uint8 = 1 byte)
     * 1-8: poolId (uint64 = 8 bytes)
     * 9-24: trancheId (16 bytes)
     * 25-56: user address (32 bytes)
     */
    function formatCollectRedeem(uint64 poolId, bytes16 trancheId, bytes32 user) internal pure returns (bytes memory) {
        return abi.encodePacked(uint8(Call.CollectRedeem), poolId, trancheId, user);
    }

    function isCollectRedeem(bytes29 _msg) internal pure returns (bool) {
        return messageType(_msg) == Call.CollectRedeem;
    }

    function parseCollectRedeem(bytes29 _msg) internal pure returns (uint64 poolId, bytes16 trancheId, bytes32 user) {
        poolId = uint64(_msg.indexUint(1, 8));
        trancheId = bytes16(_msg.index(9, 16));
        user = bytes32(_msg.index(25, 32));
    }

    /*
     * CollectForRedeem Message
     *
     * 0: call type (uint8 = 1 byte)
     * 1-8: poolId (uint64 = 8 bytes)
     * 9-24: trancheId (16 bytes)
     * 25-56: caller address (32 bytes)
     * 57-89: user address (32 bytes)
     */
    function formatCollectForRedeem(uint64 poolId, bytes16 trancheId, bytes32 caller, bytes32 user)
        internal
        pure
        returns (bytes memory)
    {
        return abi.encodePacked(uint8(Call.CollectForRedeem), poolId, trancheId, caller, user);
    }

    function isCollectForRedeem(bytes29 _msg) internal pure returns (bool) {
        return messageType(_msg) == Call.CollectForRedeem;
    }

    function parseCollectForRedeem(bytes29 _msg)
        internal
        pure
        returns (uint64 poolId, bytes16 trancheId, bytes32 caller, bytes32 user)
    {
        poolId = uint64(_msg.indexUint(1, 8));
        trancheId = bytes16(_msg.index(9, 16));
        caller = bytes32(_msg.index(25, 32));
        user = bytes32(_msg.index(57, 32));
    }

    /*
     * CollectInvest Message
     *
     * 0: call type (uint8 = 1 byte)
     * 1-8: poolId (uint64 = 8 bytes)
     * 9-24: trancheId (16 bytes)
     * 25-56: user address (32 bytes)
     */
    function formatCollectInvest(uint64 poolId, bytes16 trancheId, bytes32 user) internal pure returns (bytes memory) {
        return abi.encodePacked(uint8(Call.CollectInvest), poolId, trancheId, user);
    }

    function isCollectInvest(bytes29 _msg) internal pure returns (bool) {
        return messageType(_msg) == Call.CollectInvest;
    }

    function parseCollectInvest(bytes29 _msg) internal pure returns (uint64 poolId, bytes16 trancheId, bytes32 user) {
        poolId = uint64(_msg.indexUint(1, 8));
        trancheId = bytes16(_msg.index(9, 16));
        user = bytes32(_msg.index(25, 32));
    }

    /*
     * CollectForInvest Message
     *
     * 0: call type (uint8 = 1 byte)
     * 1-8: poolId (uint64 = 8 bytes)
     * 9-24: trancheId (16 bytes)
     * 25-56: caller address (32 bytes)
     * 57-89: user address (32 bytes)
     */
    function formatCollectForInvest(uint64 poolId, bytes16 trancheId, bytes32 caller, bytes32 user)
        internal
        pure
        returns (bytes memory)
    {
        return abi.encodePacked(uint8(Call.CollectForInvest), poolId, trancheId, caller, user);
    }

    function isCollectForInvest(bytes29 _msg) internal pure returns (bool) {
        return messageType(_msg) == Call.CollectForInvest;
    }

    function parseCollectForInvest(bytes29 _msg)
        internal
        pure
        returns (uint64 poolId, bytes16 trancheId, bytes32 caller, bytes32 user)
    {
        poolId = uint64(_msg.indexUint(1, 8));
        trancheId = bytes16(_msg.index(9, 16));
        caller = bytes32(_msg.index(25, 32));
        user = bytes32(_msg.index(57, 32));
    }

    // Utils

    function formatDomain(Domain domain) public pure returns (bytes9) {
        return bytes9(bytes1(uint8(domain)));
    }

    function formatDomain(Domain domain, uint64 domainId) public pure returns (bytes9) {
        return bytes9(abi.encodePacked(uint8(domain), domainId).ref(0).index(0, 9));
    }

    // TODO: should be moved to a util contract
    function stringToBytes32(string memory source) internal pure returns (bytes32 result) {
        bytes memory tempEmptyStringTest = bytes(source);
        if (tempEmptyStringTest.length == 0) {
            return 0x0;
        }

        assembly {
            result := mload(add(source, 32))
        }
    }

    // TODO: should be moved to a util contract
    function bytes32ToString(bytes32 _bytes32) internal pure returns (string memory) {
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
