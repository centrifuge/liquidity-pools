// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.18;

import "memview-sol/TypedMemView.sol";

library ConnectorMessages {
    using TypedMemView for bytes;
    using TypedMemView for bytes29;

    enum Call {
        Invalid,
        AddPool,
        AddTranche,
        UpdateTokenPrice,
        UpdateMember,
        Transfer
    }

    enum Domain {
        Centrifuge,
        EVM
    }

    function messageType(bytes29 _msg) internal pure returns (Call _call) {
        _call = Call(uint8(_msg.indexUint(0, 1)));
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
        return uint64(_msg.indexUint(1, 8));
    }

    /**
     * Add tranche
     *
     * 0: call type (uint8 = 1 byte)
     * 1-8: poolId (uint64 = 8 bytes)
     * 9-24: trancheId (16 bytes)
     * 25-154: tokenName (string = 128 bytes)
     * 155-187: tokenSymbol (string = 32 bytes)
     * 185-200: price (uint128 = 16 bytes)
     */
    function formatAddTranche(
        uint64 poolId,
        bytes16 trancheId,
        string memory tokenName,
        string memory tokenSymbol,
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
            price
        );
    }

    function isAddTranche(bytes29 _msg) internal pure returns (bool) {
        return messageType(_msg) == Call.AddTranche;
    }

    function parseAddTranche(bytes29 _msg)
        internal
        pure
        returns (uint64 poolId, bytes16 trancheId, string memory tokenName, string memory tokenSymbol, uint128 price)
    {
        poolId = uint64(_msg.indexUint(1, 8));
        trancheId = bytes16(_msg.index(9, 16));
        tokenName = bytes32ToString(bytes32(_msg.index(25, 32)));
        tokenSymbol = bytes32ToString(bytes32(_msg.index(153, 32)));
        price = uint128(_msg.indexUint(185, 16));
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
     * Update token price
     *
     * 0: call type (uint8 = 1 byte)
     * 1-8: poolId (uint64 = 8 bytes)
     * 9-24: trancheId (16 bytes)
     * 25-41: price (uint128 = 16 bytes)
     */
    function formatUpdateTokenPrice(uint64 poolId, bytes16 trancheId, uint128 price)
        internal
        pure
        returns (bytes memory)
    {
        return abi.encodePacked(uint8(Call.UpdateTokenPrice), poolId, trancheId, price);
    }

    function isUpdateTokenPrice(bytes29 _msg) internal pure returns (bool) {
        return messageType(_msg) == Call.UpdateTokenPrice;
    }

    function parseUpdateTokenPrice(bytes29 _msg)
        internal
        pure
        returns (uint64 poolId, bytes16 trancheId, uint128 price)
    {
        poolId = uint64(_msg.indexUint(1, 8));
        trancheId = bytes16(_msg.index(9, 16));
        price = uint128(_msg.indexUint(25, 16));
    }

    /**
     * Transfer
     *
     * 0: call type (uint8 = 1 byte)
     * 1-8: poolId (uint64 = 8 bytes)
     * 9-24: trancheId (16 bytes)
     * 25-33: destinationDomain (Domain = 9 bytes)
     * 34-65: destinationAddress (32 bytes - Either a Centrifuge chain address or an EVM address followed by 12 zeros)
     * 66-73: chainId (uint256 = 32 bytes)
     * 74-89: amount (uint128 = 16 bytes)
     */
    function formatTransfer(
        uint64 poolId,
        bytes16 trancheId,
        bytes9 destinationDomain,
        bytes32 destinationAddress,
        uint256 chainId,
        uint128 amount
    ) internal pure returns (bytes memory) {
        return abi.encodePacked(uint8(Call.Transfer), poolId, trancheId, destinationDomain, destinationAddress, chainId, amount);
    }

    // Format a transfer to an EVM domain
    // Note: This is an overload function to dry the cast from `address` to `bytes32`
    // for the `destinationAddress` field by using the default `formatTransfer` implementation
    // by appending 12 zeros to the evm-based `destinationAddress`.
    function formatTransfer(
        uint64 poolId,
        bytes16 trancheId,
        bytes9 destinationDomain,
        address destinationAddress,
        uint256 chainId,
        uint128 amount
    ) internal pure returns (bytes memory) {
        return formatTransfer(poolId, trancheId, destinationDomain, bytes32(bytes20(destinationAddress)), chainId, amount);
    }

    function isTransfer(bytes29 _msg) internal pure returns (bool) {
        return messageType(_msg) == Call.Transfer;
    }

    // Parse a Transfer to a Centrifuge-based `destinationAddress` (32-byte long)
    function parseTransfer32(bytes29 _msg)
        internal
        pure
        returns (uint64 poolId, bytes16 trancheId, bytes9 encodedDomain, bytes32 destinationAddress, uint256 chainId, uint128 amount)
    {
        poolId = uint64(_msg.indexUint(1, 8));
        trancheId = bytes16(_msg.index(9, 16));
        encodedDomain = bytes9(_msg.index(25, 9));
        destinationAddress = bytes32(_msg.index(34, 32));
        chainId = uint256(_msg.indexUint(66, 32));
        amount = uint128(_msg.indexUint(98, 16));
    }

    // Parse a Transfer to an EVM-based `destinationAddress` (20-byte long)
    function parseTransfer20(bytes29 _msg)
        internal
        pure
        returns (uint64 poolId, bytes16 trancheId, bytes9 encodedDomain, address destinationAddress, uint256 chainId, uint128 amount)
    {
        (uint64 poolId_, bytes16 trancheId_, bytes9 encodedDomain_, bytes32 destinationAddress32, uint256 chainId, uint128 amount_) =
            parseTransfer32(_msg);
        destinationAddress = address(bytes20(destinationAddress32));

        return (poolId_, trancheId_, encodedDomain_, destinationAddress, chainId, amount_);
    }

    function formatDomain(Domain domain) public pure returns (bytes9) {
        return bytes9(bytes1(uint8(domain)));
    }

    function formatDomain(Domain domain, uint64 domainId) public pure returns (bytes9) {
        return bytes9(abi.encodePacked(uint8(domain), domainId).ref(0).index(0, 9));
    }
}
