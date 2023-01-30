// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.7.6;

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
     * 9-25: trancheId (16 bytes)
     * 26-154: tokenName (string = 128 bytes)
     * 155-187: tokenSymbol (string = 32 bytes)
     */
    function formatAddTranche(uint64 poolId, bytes16 trancheId, string memory tokenName, string memory tokenSymbol) internal pure returns (bytes memory) {
        // TODO(nuno): Now, we encode `tokenName` as a 128-bytearray by first encoding `tokenName`
        // to bytes32 and then we encode three empty bytes32's, which sum up to a total of 128 bytes.
        // Add support to actually encode `tokenName` fully as a 128 bytes string.
        return abi.encodePacked(uint8(Call.AddTranche), poolId, trancheId, stringToBytes32(tokenName), bytes32(""), bytes32(""), bytes32(""), stringToBytes32(tokenSymbol));
    }

    function isAddTranche(bytes29 _msg) internal pure returns (bool) {
        return messageType(_msg) == Call.AddTranche;
    }

    function parseAddTranche(bytes29 _msg) internal pure returns (uint64 poolId, bytes16 trancheId, string memory tokenName, string memory tokenSymbol) {
        poolId = uint64(_msg.indexUint(1, 8));
        trancheId = bytes16(_msg.index(9, 16));
        tokenName = bytes32ToString(bytes32(_msg.index(25, 32)));
        tokenSymbol = bytes32ToString(bytes32(_msg.index(153, 32)));
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
        while(i < 32 && _bytes32[i] != 0) {
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
     * 9-25: trancheId (16 bytes)
     * 25-45: user (Ethereum address, 20 bytes - Skip 12 bytes from 32-byte addresses)
     * 57-65: validUntil (uint64 = 8 bytes)
     * 
     * TODO: use bytes32 for user (for non-EVM compatibility)
     */
    function formatUpdateMember(uint64 poolId, bytes16 trancheId, address user, uint64 validUntil) internal pure returns (bytes memory) {
        return abi.encodePacked(uint8(Call.UpdateMember), poolId, trancheId, user, validUntil);
    }

    function isUpdateMember(bytes29 _msg) internal pure returns (bool) {
        return messageType(_msg) == Call.UpdateMember;
    }


    function parseUpdateMember(bytes29 _msg) internal pure returns (uint64 poolId, bytes16 trancheId, address user, uint64 validUntil) {
        poolId = uint64(_msg.indexUint(1, 8));
        trancheId = bytes16(_msg.index(9, 16));
        user = address(bytes20(_msg.index(25, 20)));
        validUntil = uint64(_msg.indexUint(57, 8));
    }

    // Convert an hexadecimal character to their value
    function fromHexChar(uint8 c) internal pure returns (uint8) {
        if (bytes1(c) >= bytes1("0") && bytes1(c) <= bytes1("9")) {
            return c - uint8(bytes1("0"));
        }
        if (bytes1(c) >= bytes1("a") && bytes1(c) <= bytes1("f")) {
            return 10 + c - uint8(bytes1("a"));
        }
        if (bytes1(c) >= bytes1("A") && bytes1(c) <= bytes1("F")) {
            return 10 + c - uint8(bytes1("A"));
        }
        revert("Failed to encode hex char");
    }

    // Convert an hexadecimal string to raw bytes
    function fromHex(string memory s) internal pure returns (bytes memory) {
        bytes memory ss = bytes(s);
        require(ss.length % 2 == 0); // length must be even
        bytes memory r = new bytes(ss.length / 2);

        for (uint256 i = 0; i < ss.length / 2; ++i) {
            r[i] = bytes1(
                fromHexChar(uint8(ss[2 * i])) *
                16 +
                fromHexChar(uint8(ss[2 * i + 1]))
            );
        }
        return r;
    }

    /**
     * Update token price
     * 
     * 0: call type (uint8 = 1 byte)
     * 1-8: poolId (uint64 = 8 bytes)
     * 9-25: trancheId (16 bytes)
     * 26-58: price (uint256 = 32 bytes)
     */
    function formatUpdateTokenPrice(uint64 poolId, bytes16 trancheId, uint256 price) internal pure returns (bytes memory) {
        return abi.encodePacked(uint8(Call.UpdateTokenPrice), poolId, trancheId, price);
    }

    function isUpdateTokenPrice(bytes29 _msg) internal pure returns (bool) {
        return messageType(_msg) == Call.UpdateTokenPrice;
    }

    function parseUpdateTokenPrice(bytes29 _msg) internal pure returns (uint64 poolId, bytes16 trancheId, uint256 price) {
        poolId = uint64(_msg.indexUint(1, 8));
        trancheId = bytes16(_msg.index(9, 16));
        price = uint256(_msg.index(25, 32));
    }

     /**
     * Transfer
     * 
     * 0: call type (uint8 = 1 byte)
     * 1-8: poolId (uint64 = 8 bytes)
     * 9-25: trancheId (16 bytes)
     * 26-46: user (Ethereum address, 20 bytes)
     * 47-78: amount (uint256 = 32 bytes)
     * 
     */
    function formatTransfer(uint64 poolId, bytes16 trancheId, address user, uint256 amount) internal pure returns (bytes memory) {
        return abi.encodePacked(uint8(Call.Transfer), poolId, trancheId, user, amount);
    }

    function isTransfer(bytes29 _msg) internal pure returns (bool) {
        return messageType(_msg) == Call.Transfer;
    }

    function parseTransfer(bytes29 _msg) internal pure returns (uint64 poolId, bytes16 trancheId, address user, uint256 amount) {
        poolId = uint64(_msg.indexUint(1, 8));
        trancheId = bytes16(_msg.index(9, 16));
        user = address(bytes20(_msg.index(25, 20)));
        amount = uint256(_msg.index(45, 32));
    }

}