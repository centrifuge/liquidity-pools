// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.18;
pragma abicoder v2;

import {TypedMemView} from "memview-sol/TypedMemView.sol";
import {ConnectorMessages} from "src/Messages.sol";
import "forge-std/Test.sol";

contract MessagesTest is Test {
    using TypedMemView for bytes;
    using TypedMemView for bytes29;
    using ConnectorMessages for bytes29;

    function setUp() public {}

    function testAddCurrencyEncoding() public {
        assertEq(
            ConnectorMessages.formatAddCurrency(42, 0x1234567890123456789012345678901234567890),
            fromHex("010000000000000000000000000000002a1234567890123456789012345678901234567890")
        );
    }

    function testAddCurrencyDecoding() public {
        (uint128 currency, address currencyAddress) = ConnectorMessages.parseAddCurrency(
            fromHex("010000000000000000000000000000002a1234567890123456789012345678901234567890").ref(0)
        );
        assertEq(uint256(currency), 42);
        assertEq(currencyAddress, 0x1234567890123456789012345678901234567890);
    }

    function testAddCurrencyEquivalence(uint128 currency, address currencyAddress) public {
        bytes memory _message = ConnectorMessages.formatAddCurrency(currency, currencyAddress);
        (uint128 decodedCurrency, address decodedCurrencyAddress) = ConnectorMessages.parseAddCurrency(_message.ref(0));
        assertEq(decodedCurrency, uint256(currency));
        assertEq(decodedCurrencyAddress, currencyAddress);
    }

    function testAddPoolEncoding() public {
        assertEq(ConnectorMessages.formatAddPool(0), fromHex("020000000000000000"));
        assertEq(ConnectorMessages.formatAddPool(1), fromHex("020000000000000001"));
        assertEq(ConnectorMessages.formatAddPool(12378532), fromHex("020000000000bce1a4"));
    }

    function testAddPoolDecoding() public {
        (uint64 actualPoolId1) = ConnectorMessages.parseAddPool(fromHex("020000000000000000").ref(0));
        assertEq(uint256(actualPoolId1), 0);

        (uint64 actualPoolId2) = ConnectorMessages.parseAddPool(fromHex("020000000000000001").ref(0));
        assertEq(uint256(actualPoolId2), 1);

        (uint64 actualPoolId3) = ConnectorMessages.parseAddPool(fromHex("020000000000bce1a4").ref(0));
        assertEq(uint256(actualPoolId3), 12378532);
    }

    function testAddPoolEquivalence(uint64 poolId) public {
        bytes memory _message = ConnectorMessages.formatAddPool(poolId);
        (uint64 decodedPoolId) = ConnectorMessages.parseAddPool(_message.ref(0));
        assertEq(decodedPoolId, uint256(poolId));
    }

    function testAllowPoolCurrencyEncoding() public {
        assertEq(
            ConnectorMessages.formatAllowPoolCurrency(42, 99), hex"030000000000000000000000000000002a0000000000000063"
        );
    }

    function testAllowPoolCurrencyDecoding() public {
        (uint128 actualCurrency, uint64 actualPoolId) = ConnectorMessages.parseAllowPoolCurrency(
            fromHex("030000000000000000000000000000002a0000000000000063").ref(0)
        );
        assertEq(uint256(actualCurrency), 42);
        assertEq(actualPoolId, 99);
    }

    function testAllowPoolCurrencyEquivalence(uint128 currency, uint64 poolId) public {
        bytes memory _message = ConnectorMessages.formatAllowPoolCurrency(currency, poolId);
        (uint128 decodedCurrency, uint64 decodedPoolId) = ConnectorMessages.parseAllowPoolCurrency(_message.ref(0));
        assertEq(decodedCurrency, uint256(currency));
        assertEq(uint256(decodedPoolId), uint256(poolId));
    }

    function testAddTrancheEncoding() public {
        assertEq(
            ConnectorMessages.formatAddTranche(
                12378532,
                bytes16(hex"811acd5b3f17c06841c7e41e9e04cb1b"),
                "Some Name",
                "SYMBOL",
                18,
                1000000000000000000000000000
            ),
            hex"040000000000bce1a4811acd5b3f17c06841c7e41e9e04cb1b536f6d65204e616d65000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000053594d424f4c00000000000000000000000000000000000000000000000000001200000000033b2e3c9fd0803ce8000000"
        );
    }

    function testAddTrancheDecoding() public {
        (
            uint64 decodedPoolId,
            bytes16 decodedTrancheId,
            string memory decodedTokenName,
            string memory decodedTokenSymbol,
            uint8 decodedDecimals,
            uint128 decodedPrice
        ) = ConnectorMessages.parseAddTranche(
            fromHex(
                "040000000000bce1a4811acd5b3f17c06841c7e41e9e04cb1b536f6d65204e616d65000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000053594d424f4c00000000000000000000000000000000000000000000000000001200000000033b2e3c9fd0803ce8000000"
            ).ref(0)
        );
        assertEq(uint256(decodedPoolId), uint256(12378532));
        assertEq(decodedTrancheId, bytes16(hex"811acd5b3f17c06841c7e41e9e04cb1b"));
        assertEq(decodedTokenName, bytes32ToString(bytes32("Some Name")));
        assertEq(decodedTokenSymbol, bytes32ToString(bytes32("SYMBOL")));
        assertEq(decodedDecimals, 18);
        assertEq(decodedPrice, uint256(1000000000000000000000000000));
    }

    function testAddTrancheEquivalence(
        uint64 poolId,
        bytes16 trancheId,
        string memory tokenName,
        string memory tokenSymbol,
        uint8 decimals,
        uint128 price
    ) public {
        bytes memory _message =
            ConnectorMessages.formatAddTranche(poolId, trancheId, tokenName, tokenSymbol, decimals, price);
        (
            uint64 decodedPoolId,
            bytes16 decodedTrancheId,
            string memory decodedTokenName,
            string memory decodedTokenSymbol,
            uint8 decodedDecimals,
            uint128 decodedPrice
        ) = ConnectorMessages.parseAddTranche(_message.ref(0));
        assertEq(uint256(decodedPoolId), uint256(poolId));
        assertEq(decodedTrancheId, trancheId);
        // Comparing raw input to output can erroneously fail when a byte string is given.
        // Intended behaviour is that byte strings will be treated as bytes and converted to strings instead
        // of treated as strings themselves. This conversion from string to bytes32 to string is used to simulate
        // this intended behaviour.
        assertEq(decodedTokenName, bytes32ToString(stringToBytes32(tokenName)));
        assertEq(decodedTokenSymbol, bytes32ToString(stringToBytes32(tokenSymbol)));
        assertEq(decodedDecimals, decimals);
        assertEq(uint256(decodedPrice), uint256(price));
    }

    // Note: UpdateMember encodes differently in Solidity compared to the Rust counterpart because `user` is a 20-byte
    // value in Solidity while it is 32-byte in Rust. However, UpdateMember messages coming from the cent-chain will
    // be handled correctly as the last 12 bytes out of said 32 will be ignored.
    function testUpdateMemberEncoding() public {
        assertEq(
            ConnectorMessages.formatUpdateMember(
                2,
                bytes16(hex"811acd5b3f17c06841c7e41e9e04cb1b"),
                0x1231231231231231231231231231231231231231,
                1706260138
            ),
            hex"060000000000000002811acd5b3f17c06841c7e41e9e04cb1b12312312312312312312312312312312312312310000000000000000000000000000000065b376aa"
        );
    }

    // We use an UpdateMember encoded message generated in the cent-chain to
    // verify we handle the 32 to 20 bytes address compatibility as expected.
    function testUpdateMemberDecoding() public {
        (uint64 decodedPoolId, bytes16 decodedTrancheId, address decodedUser, uint64 decodedValidUntil) =
        ConnectorMessages.parseUpdateMember(
            fromHex(
                "040000000000000002811acd5b3f17c06841c7e41e9e04cb1b12312312312312312312312312312312312312312312312312312312312312310000000065b376aa"
            ).ref(0)
        );
        assertEq(uint256(decodedPoolId), uint256(2));
        assertEq(decodedTrancheId, hex"811acd5b3f17c06841c7e41e9e04cb1b");
        assertEq(decodedUser, 0x1231231231231231231231231231231231231231);
        assertEq(decodedValidUntil, uint256(1706260138));
    }

    function testUpdateMemberEquivalence(uint64 poolId, bytes16 trancheId, address user, uint64 validUntil) public {
        bytes memory _message = ConnectorMessages.formatUpdateMember(poolId, trancheId, user, validUntil);
        (uint64 decodedPoolId, bytes16 decodedTrancheId, address decodedUser, uint64 decodedValidUntil) =
            ConnectorMessages.parseUpdateMember(_message.ref(0));
        assertEq(uint256(decodedPoolId), uint256(poolId));
        assertEq(decodedTrancheId, trancheId);
        assertEq(decodedUser, user);
        assertEq(uint256(decodedValidUntil), uint256(validUntil));
    }

    function testUpdateTrancheTokenPriceEncoding() public {
        assertEq(
            ConnectorMessages.formatUpdateTrancheTokenPrice(
                1, bytes16(hex"811acd5b3f17c06841c7e41e9e04cb1b"), 1000000000000000000000000000
            ),
            fromHex("050000000000000001811acd5b3f17c06841c7e41e9e04cb1b00000000033b2e3c9fd0803ce8000000")
        );
    }

    function testUpdateTrancheTokenPriceDecoding() public {
        (uint64 decodedPoolId, bytes16 decodedTrancheId, uint128 decodedPrice) = ConnectorMessages
            .parseUpdateTrancheTokenPrice(
            fromHex("030000000000000001811acd5b3f17c06841c7e41e9e04cb1b00000000033b2e3c9fd0803ce8000000").ref(0)
        );
        assertEq(uint256(decodedPoolId), uint256(1));
        assertEq(decodedTrancheId, bytes16(hex"811acd5b3f17c06841c7e41e9e04cb1b"));
        assertEq(decodedPrice, uint256(1000000000000000000000000000));
    }

    function testUpdateTrancheTokenPriceEquivalence(uint64 poolId, bytes16 trancheId, uint128 price) public {
        bytes memory _message = ConnectorMessages.formatUpdateTrancheTokenPrice(poolId, trancheId, price);
        (uint64 decodedPoolId, bytes16 decodedTrancheId, uint128 decodedPrice) =
            ConnectorMessages.parseUpdateTrancheTokenPrice(_message.ref(0));
        assertEq(uint256(decodedPoolId), uint256(poolId));
        assertEq(decodedTrancheId, trancheId);
        assertEq(uint256(decodedPrice), uint256(price));
    }

    function testTransferEncoding() public {
        assertEq(
            ConnectorMessages.formatTransfer(
                uint128(42),
                0x1111111111111111111111111111111111111111111111111111111111111111,
                0x2222222222222222222222222222222222222222222222222222222222222222,
                1000000000000000000000000000
            ),
            hex"070000000000000000000000000000002a1111111111111111111111111111111111111111111111111111111111111111222222222222222222222222222222222222222222222222222222222222222200000000033b2e3c9fd0803ce8000000"
        );
    }

    function testTransferDecoding() public {
        bytes29 message = fromHex(
            "070000000000000000000000000000002a1111111111111111111111111111111111111111111111111111111111111111222222222222222222222222222222222222222222222222222222222222222200000000033b2e3c9fd0803ce8000000"
        ).ref(0);

        (uint128 token, bytes32 sender, bytes32 recipient, uint128 amount) = ConnectorMessages.parseTransfer(message);
        assertEq(uint256(token), uint256(42));
        assertEq(sender, 0x1111111111111111111111111111111111111111111111111111111111111111);
        assertEq(recipient, 0x2222222222222222222222222222222222222222222222222222222222222222);
        assertEq(amount, uint256(1000000000000000000000000000));

        // Test the optimised `parseIncomingTransfer` now
        (uint128 token2, address recipient2, uint128 amount2) = ConnectorMessages.parseIncomingTransfer(message);
        assertEq(uint256(token2), uint256(token));
        assertEq(recipient2, address(bytes20(recipient)));
        assertEq(amount, amount2);
    }

    function testTransferEquivalence(uint128 token, bytes32 sender, bytes32 receiver, uint128 amount) public {
        bytes memory _message = ConnectorMessages.formatTransfer(token, sender, receiver, amount);
        (uint128 decodedToken, bytes32 decodedSender, bytes32 decodedReceiver, uint128 decodedAmount) =
            ConnectorMessages.parseTransfer(_message.ref(0));
        assertEq(uint256(decodedToken), uint256(token));
        assertEq(decodedSender, sender);
        assertEq(decodedReceiver, receiver);
        assertEq(decodedAmount, amount);

        // Test the optimised `parseIncomingTransfer` now
        (uint128 decodedToken2, address decodedRecipient2, uint128 decodedAmount2) =
            ConnectorMessages.parseIncomingTransfer(_message.ref(0));
        assertEq(uint256(decodedToken2), uint256(decodedToken));
        assertEq(decodedRecipient2, address(bytes20(decodedReceiver)));
        assertEq(decodedAmount, decodedAmount2);
    }

    function testTransferTrancheTokensToEvmDomainEncoding() public {
        assertEq(
            ConnectorMessages.formatTransferTrancheTokens(
                1,
                bytes16(hex"811acd5b3f17c06841c7e41e9e04cb1b"),
                ConnectorMessages.formatDomain(ConnectorMessages.Domain.EVM, 1284),
                1,
                0x1231231231231231231231231231231231231231,
                1000000000000000000000000000
            ),
            hex"080000000000000001811acd5b3f17c06841c7e41e9e04cb1b0100000000000005040000000000000000000000000000000000000000000000000000000000000001123123123123123123123123123123123123123100000000000000000000000000000000033b2e3c9fd0803ce8000000"
        );
    }

    function testTransferTrancheTokensToEvmDomainDecoding() public {
        (
            uint64 poolId,
            bytes16 trancheId,
            bytes9 domain,
            uint256 destinationChainId,
            address destinationAddress,
            uint128 amount
        ) = ConnectorMessages.parseTransferTrancheTokens20(
            fromHex(
                "080000000000000001811acd5b3f17c06841c7e41e9e04cb1b0100000000000005040000000000000000000000000000000000000000000000000000000000000001123123123123123123123123123123123123123100000000000000000000000000000000033b2e3c9fd0803ce8000000"
            ).ref(0)
        );
        assertEq(uint256(poolId), uint256(1));
        assertEq(trancheId, bytes16(hex"811acd5b3f17c06841c7e41e9e04cb1b"));
        assertEq(domain, ConnectorMessages.formatDomain(ConnectorMessages.Domain.EVM, 1284));
        assertEq(destinationChainId, uint256(1));
        assertEq(destinationAddress, 0x1231231231231231231231231231231231231231);
        assertEq(amount, uint256(1000000000000000000000000000));
    }

    function testTransferTrancheTokensToCentrifugeEncoding() public {
        assertEq(
            ConnectorMessages.formatTransferTrancheTokens(
                1,
                bytes16(hex"811acd5b3f17c06841c7e41e9e04cb1b"),
                ConnectorMessages.formatDomain(ConnectorMessages.Domain.Centrifuge),
                1,
                0x1231231231231231231231231231231231231231231231231231231231231231,
                1000000000000000000000000000
            ),
            hex"080000000000000001811acd5b3f17c06841c7e41e9e04cb1b0000000000000000000000000000000000000000000000000000000000000000000000000000000001123123123123123123123123123123123123123123123123123123123123123100000000033b2e3c9fd0803ce8000000"
        );
    }

    function testTransferTrancheTokensToCentrifugeDecoding() public {
        (
            uint64 poolId,
            bytes16 trancheId,
            bytes9 domain,
            uint256 destinationChainId,
            bytes32 destinationAddress,
            uint128 amount
        ) = ConnectorMessages.parseTransferTrancheTokens32(
            fromHex(
                "080000000000000001811acd5b3f17c06841c7e41e9e04cb1b0000000000000000000000000000000000000000000000000000000000000000000000000000000001123123123123123123123123123123123123123123123123123123123123123100000000033b2e3c9fd0803ce8000000"
            ).ref(0)
        );
        assertEq(uint256(poolId), uint256(1));
        assertEq(trancheId, bytes16(hex"811acd5b3f17c06841c7e41e9e04cb1b"));
        assertEq(domain, ConnectorMessages.formatDomain(ConnectorMessages.Domain.Centrifuge));
        assertEq(destinationAddress, bytes32(hex"1231231231231231231231231231231231231231231231231231231231231231"));
        assertEq(destinationChainId, uint256(1));
        assertEq(amount, uint256(1000000000000000000000000000));
    }

    function testTransferTrancheTokensToEvmEquivalence(
        uint64 poolId,
        bytes16 trancheId,
        uint256 destinationChainId,
        address destinationAddress,
        uint128 amount
    ) public {
        bytes9 inputEncodedDomain = ConnectorMessages.formatDomain(ConnectorMessages.Domain.EVM);
        bytes memory _message = ConnectorMessages.formatTransferTrancheTokens(
            poolId, trancheId, inputEncodedDomain, destinationChainId, destinationAddress, amount
        );
        (
            uint64 decodedPoolId,
            bytes16 decodedTrancheId,
            bytes9 encodedDomain,
            uint256 decodeddestinationChainId,
            address decodedDestinationAddress,
            uint256 decodedAmount
        ) = ConnectorMessages.parseTransferTrancheTokens20(_message.ref(0));
        assertEq(uint256(decodedPoolId), uint256(poolId));
        assertEq(decodedTrancheId, trancheId);
        assertEq(encodedDomain, inputEncodedDomain);
        assertEq(decodedDestinationAddress, destinationAddress);
        assertEq(decodeddestinationChainId, destinationChainId);
        assertEq(decodedAmount, amount);
    }

    function testTransferTrancheTokensToCentrifugeEquivalence(
        uint64 poolId,
        bytes16 trancheId,
        bytes32 destinationAddress,
        uint128 amount
    ) public {
        bytes9 inputEncodedDomain = ConnectorMessages.formatDomain(ConnectorMessages.Domain.Centrifuge);
        bytes memory _message = ConnectorMessages.formatTransferTrancheTokens(
            poolId, trancheId, inputEncodedDomain, 0, destinationAddress, amount
        );
        (
            uint64 decodedPoolId,
            bytes16 decodedTrancheId,
            bytes9 encodedDomain,
            uint256 decodeddestinationChainId,
            bytes32 decodedDestinationAddress,
            uint256 decodedAmount
        ) = ConnectorMessages.parseTransferTrancheTokens32(_message.ref(0));
        assertEq(uint256(decodedPoolId), uint256(poolId));
        assertEq(decodedTrancheId, trancheId);
        assertEq(encodedDomain, inputEncodedDomain);
        assertEq(decodedDestinationAddress, destinationAddress);
        assertEq(decodeddestinationChainId, 0);
        assertEq(decodedAmount, amount);
    }

    // IncreaseInvestOrder
    function testIncreaseInvestOrderEncoding() public {
        assertEq(
            ConnectorMessages.formatIncreaseInvestOrder(
                2,
                bytes16(hex"811acd5b3f17c06841c7e41e9e04cb1b"),
                0x1231231231231231231231231231231231231231231231231231231231231231,
                uint128(42),
                1706260138
            ),
            hex"090000000000000002811acd5b3f17c06841c7e41e9e04cb1b12312312312312312312312312312312312312312312312312312312312312310000000000000000000000000000002a00000000000000000000000065b376aa"
        );
    }

    function testIncreaseInvestOrderDecoding() public {
        (uint64 decodedPoolId, bytes16 decodedTrancheId, bytes32 decodedInvestor, uint128 token, uint128 amount) =
        ConnectorMessages.parseIncreaseInvestOrder(
            fromHex(
                "090000000000000002811acd5b3f17c06841c7e41e9e04cb1b12312312312312312312312312312312312312312312312312312312312312310000000000000000000000000000002a00000000000000000000000065b376aa"
            ).ref(0)
        );
        assertEq(uint256(decodedPoolId), uint256(2));
        assertEq(decodedTrancheId, hex"811acd5b3f17c06841c7e41e9e04cb1b");
        assertEq(decodedInvestor, 0x1231231231231231231231231231231231231231231231231231231231231231);
        assertEq(token, uint128(42));
        assertEq(amount, uint128(1706260138));
    }

    function testIncreaseInvestOrderEquivalence(
        uint64 poolId,
        bytes16 trancheId,
        bytes32 investor,
        uint128 token,
        uint128 amount
    ) public {
        bytes memory _message = ConnectorMessages.formatIncreaseInvestOrder(poolId, trancheId, investor, token, amount);
        (
            uint64 decodedPoolId,
            bytes16 decodedTrancheId,
            bytes32 decodedInvestor,
            uint128 decodedToken,
            uint128 decodedAmount
        ) = ConnectorMessages.parseIncreaseInvestOrder(_message.ref(0));

        assertEq(uint256(decodedPoolId), uint256(poolId));
        assertEq(decodedTrancheId, trancheId);
        assertEq(decodedInvestor, investor);
        assertEq(decodedToken, token);
        assertEq(decodedAmount, amount);
    }

    // DecreaseInvestOrder
    function testDecreaseInvestOrderEncoding() public {
        assertEq(
            ConnectorMessages.formatDecreaseInvestOrder(
                2,
                bytes16(hex"811acd5b3f17c06841c7e41e9e04cb1b"),
                0x1231231231231231231231231231231231231231231231231231231231231231,
                uint128(42),
                1706260138
            ),
            hex"0a0000000000000002811acd5b3f17c06841c7e41e9e04cb1b12312312312312312312312312312312312312312312312312312312312312310000000000000000000000000000002a00000000000000000000000065b376aa"
        );
    }

    function testDecreaseInvestOrderDecoding() public {
        (uint64 decodedPoolId, bytes16 decodedTrancheId, bytes32 decodedInvestor, uint128 token, uint128 amount) =
        ConnectorMessages.parseDecreaseInvestOrder(
            fromHex(
                "0a0000000000000002811acd5b3f17c06841c7e41e9e04cb1b12312312312312312312312312312312312312312312312312312312312312310000000000000000000000000000002a00000000000000000000000065b376aa"
            ).ref(0)
        );
        assertEq(uint256(decodedPoolId), uint256(2));
        assertEq(decodedTrancheId, hex"811acd5b3f17c06841c7e41e9e04cb1b");
        assertEq(decodedInvestor, 0x1231231231231231231231231231231231231231231231231231231231231231);
        assertEq(token, uint128(42));
        assertEq(amount, uint128(1706260138));
    }

    function testDecreaseInvestOrderEquivalence(
        uint64 poolId,
        bytes16 trancheId,
        bytes32 investor,
        uint128 token,
        uint128 amount
    ) public {
        bytes memory _message = ConnectorMessages.formatDecreaseInvestOrder(poolId, trancheId, investor, token, amount);
        (
            uint64 decodedPoolId,
            bytes16 decodedTrancheId,
            bytes32 decodedInvestor,
            uint128 decodedToken,
            uint128 decodedAmount
        ) = ConnectorMessages.parseDecreaseInvestOrder(_message.ref(0));

        assertEq(uint256(decodedPoolId), uint256(poolId));
        assertEq(decodedTrancheId, trancheId);
        assertEq(decodedInvestor, investor);
        assertEq(decodedToken, token);
        assertEq(decodedAmount, amount);
    }

    // IncreaseRedeemOrder
    function testIncreaseRedeemOrderEncoding() public {
        assertEq(
            ConnectorMessages.formatIncreaseRedeemOrder(
                2,
                bytes16(hex"811acd5b3f17c06841c7e41e9e04cb1b"),
                0x1231231231231231231231231231231231231231231231231231231231231231,
                uint128(42),
                1706260138
            ),
            hex"0b0000000000000002811acd5b3f17c06841c7e41e9e04cb1b12312312312312312312312312312312312312312312312312312312312312310000000000000000000000000000002a00000000000000000000000065b376aa"
        );
    }

    function testIncreaseRedeemOrderDecoding() public {
        (uint64 decodedPoolId, bytes16 decodedTrancheId, bytes32 decodedInvestor, uint128 token, uint128 amount) =
        ConnectorMessages.parseIncreaseRedeemOrder(
            fromHex(
                "0b0000000000000002811acd5b3f17c06841c7e41e9e04cb1b12312312312312312312312312312312312312312312312312312312312312310000000000000000000000000000002a00000000000000000000000065b376aa"
            ).ref(0)
        );
        assertEq(uint256(decodedPoolId), uint256(2));
        assertEq(decodedTrancheId, hex"811acd5b3f17c06841c7e41e9e04cb1b");
        assertEq(decodedInvestor, 0x1231231231231231231231231231231231231231231231231231231231231231);
        assertEq(token, uint128(42));
        assertEq(amount, uint128(1706260138));
    }

    function testIncreaseRedeemOrderEquivalence(
        uint64 poolId,
        bytes16 trancheId,
        bytes32 investor,
        uint128 token,
        uint128 amount
    ) public {
        bytes memory _message = ConnectorMessages.formatIncreaseRedeemOrder(poolId, trancheId, investor, token, amount);
        (
            uint64 decodedPoolId,
            bytes16 decodedTrancheId,
            bytes32 decodedInvestor,
            uint128 decodedToken,
            uint128 decodedAmount
        ) = ConnectorMessages.parseIncreaseRedeemOrder(_message.ref(0));

        assertEq(uint256(decodedPoolId), uint256(poolId));
        assertEq(decodedTrancheId, trancheId);
        assertEq(decodedInvestor, investor);
        assertEq(decodedToken, token);
        assertEq(decodedAmount, amount);
    }

    // DecreaseRedeemOrder
    function testDecreaseRedeemOrderEncoding() public {
        assertEq(
            ConnectorMessages.formatDecreaseRedeemOrder(
                2,
                bytes16(hex"811acd5b3f17c06841c7e41e9e04cb1b"),
                0x1231231231231231231231231231231231231231231231231231231231231231,
                uint128(42),
                1706260138
            ),
            hex"0c0000000000000002811acd5b3f17c06841c7e41e9e04cb1b12312312312312312312312312312312312312312312312312312312312312310000000000000000000000000000002a00000000000000000000000065b376aa"
        );
    }

    function testDecreaseRedeemOrderDecoding() public {
        (uint64 decodedPoolId, bytes16 decodedTrancheId, bytes32 decodedInvestor, uint128 token, uint128 amount) =
        ConnectorMessages.parseDecreaseRedeemOrder(
            fromHex(
                "0c0000000000000002811acd5b3f17c06841c7e41e9e04cb1b12312312312312312312312312312312312312312312312312312312312312310000000000000000000000000000002a00000000000000000000000065b376aa"
            ).ref(0)
        );
        assertEq(uint256(decodedPoolId), uint256(2));
        assertEq(decodedTrancheId, hex"811acd5b3f17c06841c7e41e9e04cb1b");
        assertEq(decodedInvestor, 0x1231231231231231231231231231231231231231231231231231231231231231);
        assertEq(token, uint128(42));
        assertEq(amount, uint128(1706260138));
    }

    function testDecreaseRedeemOrderEquivalence(
        uint64 poolId,
        bytes16 trancheId,
        bytes32 investor,
        uint128 token,
        uint128 amount
    ) public {
        bytes memory _message = ConnectorMessages.formatDecreaseRedeemOrder(poolId, trancheId, investor, token, amount);
        (
            uint64 decodedPoolId,
            bytes16 decodedTrancheId,
            bytes32 decodedInvestor,
            uint128 decodedToken,
            uint128 decodedAmount
        ) = ConnectorMessages.parseDecreaseRedeemOrder(_message.ref(0));

        assertEq(uint256(decodedPoolId), uint256(poolId));
        assertEq(decodedTrancheId, trancheId);
        assertEq(decodedInvestor, investor);
        assertEq(decodedToken, token);
        assertEq(decodedAmount, amount);
    }

    // CollectRedeem
    function testCollectRedeemEncoding() public {
        assertEq(
            ConnectorMessages.formatCollectRedeem(
                2,
                bytes16(hex"811acd5b3f17c06841c7e41e9e04cb1b"),
                0x1231231231231231231231231231231231231231231231231231231231231231
            ),
            hex"0d0000000000000002811acd5b3f17c06841c7e41e9e04cb1b1231231231231231231231231231231231231231231231231231231231231231"
        );
    }

    function testCollectRedeemDecoding() public {
        (uint64 decodedPoolId, bytes16 decodedTrancheId, bytes32 decodedUser) = ConnectorMessages.parseCollectRedeem(
            fromHex(
                "0d0000000000000002811acd5b3f17c06841c7e41e9e04cb1b1231231231231231231231231231231231231231231231231231231231231231"
            ).ref(0)
        );
        assertEq(uint256(decodedPoolId), uint256(2));
        assertEq(decodedTrancheId, hex"811acd5b3f17c06841c7e41e9e04cb1b");
        assertEq(decodedUser, 0x1231231231231231231231231231231231231231231231231231231231231231);
    }

    function testCollectRedeemEquivalence(uint64 poolId, bytes16 trancheId, bytes32 user) public {
        bytes memory _message = ConnectorMessages.formatCollectRedeem(poolId, trancheId, user);
        (uint64 decodedPoolId, bytes16 decodedTrancheId, bytes32 decodedUser) =
            ConnectorMessages.parseCollectRedeem(_message.ref(0));

        assertEq(uint256(decodedPoolId), uint256(poolId));
        assertEq(decodedTrancheId, trancheId);
        assertEq(decodedUser, user);
    }

    // CollectInvest
    function testCollectInvestEncoding() public {
        assertEq(
            ConnectorMessages.formatCollectInvest(
                2,
                bytes16(hex"811acd5b3f17c06841c7e41e9e04cb1b"),
                0x1231231231231231231231231231231231231231231231231231231231231231
            ),
            hex"0e0000000000000002811acd5b3f17c06841c7e41e9e04cb1b1231231231231231231231231231231231231231231231231231231231231231"
        );
    }

    function testCollectInvestDecoding() public {
        (uint64 decodedPoolId, bytes16 decodedTrancheId, bytes32 decodedUser) = ConnectorMessages.parseCollectInvest(
            fromHex(
                "0f0000000000000002811acd5b3f17c06841c7e41e9e04cb1b1231231231231231231231231231231231231231231231231231231231231231"
            ).ref(0)
        );
        assertEq(uint256(decodedPoolId), uint256(2));
        assertEq(decodedTrancheId, hex"811acd5b3f17c06841c7e41e9e04cb1b");
        assertEq(decodedUser, 0x1231231231231231231231231231231231231231231231231231231231231231);
    }

    function testCollectInvestEquivalence(uint64 poolId, bytes16 trancheId, bytes32 user) public {
        bytes memory _message = ConnectorMessages.formatCollectInvest(poolId, trancheId, user);
        (uint64 decodedPoolId, bytes16 decodedTrancheId, bytes32 decodedUser) =
            ConnectorMessages.parseCollectInvest(_message.ref(0));

        assertEq(uint256(decodedPoolId), uint256(poolId));
        assertEq(decodedTrancheId, trancheId);
        assertEq(decodedUser, user);
    }

    function testFormatDomainCentrifuge() public {
        assertEq(ConnectorMessages.formatDomain(ConnectorMessages.Domain.Centrifuge), hex"000000000000000000");
    }

    function testFormatDomainMoonbeam() public {
        assertEq(ConnectorMessages.formatDomain(ConnectorMessages.Domain.EVM, 1284), hex"010000000000000504");
    }

    function testFormatDomainMoonbaseAlpha() public {
        assertEq(ConnectorMessages.formatDomain(ConnectorMessages.Domain.EVM, 1287), hex"010000000000000507");
    }

    function testFormatDomainAvalanche() public {
        assertEq(ConnectorMessages.formatDomain(ConnectorMessages.Domain.EVM, 43114), hex"01000000000000a86a");
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
            r[i] = bytes1(fromHexChar(uint8(ss[2 * i])) * 16 + fromHexChar(uint8(ss[2 * i + 1])));
        }
        return r;
    }

    function stringToBytes32(string memory source) internal pure returns (bytes32 result) {
        bytes memory tempEmptyStringTest = bytes(source);
        if (tempEmptyStringTest.length == 0) {
            return 0x0;
        }

        assembly {
            result := mload(add(source, 32))
        }
    }

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
