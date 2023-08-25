// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.18;
pragma abicoder v2;

import {TypedMemView} from "memview-sol/TypedMemView.sol";
import {Messages} from "src/Messages.sol";
import "forge-std/Test.sol";

contract MessagesTest is Test {
    using TypedMemView for bytes;
    using TypedMemView for bytes29;
    using Messages for bytes29;

    function setUp() public {}

    function testAddCurrency() public {
        uint128 currency = 246803579;
        address currencyAddress = 0x1231231231231231231231231231231231231231;
        bytes memory expectedHex = hex"010000000000000000000000000eb5ec7b1231231231231231231231231231231231231231";

        assertEq(Messages.formatAddCurrency(currency, currencyAddress), expectedHex);

        (uint128 decodedCurrency, address decodedCurrencyAddress) = Messages.parseAddCurrency(expectedHex.ref(0));
        assertEq(uint256(decodedCurrency), currency);
        assertEq(decodedCurrencyAddress, currencyAddress);
    }

    function testAddCurrencyEquivalence(uint128 currency, address currencyAddress) public {
        bytes memory _message = Messages.formatAddCurrency(currency, currencyAddress);
        (uint128 decodedCurrency, address decodedCurrencyAddress) = Messages.parseAddCurrency(_message.ref(0));
        assertEq(decodedCurrency, uint256(currency));
        assertEq(decodedCurrencyAddress, currencyAddress);
    }

    function testAddPool() public {
        uint64 poolId = 12378532;
        bytes memory expectedHex = hex"020000000000bce1a4";

        assertEq(Messages.formatAddPool(poolId), expectedHex);

        (uint64 decodedPoolId) = Messages.parseAddPool(expectedHex.ref(0));
        assertEq(uint256(decodedPoolId), poolId);
    }

    function testAddPoolEquivalence(uint64 poolId) public {
        bytes memory _message = Messages.formatAddPool(poolId);
        (uint64 decodedPoolId) = Messages.parseAddPool(_message.ref(0));
        assertEq(decodedPoolId, uint256(poolId));
    }

    function testAllowPoolCurrency() public {
        uint64 poolId = 12378532;
        uint128 currency = 246803579;
        bytes memory expectedHex = hex"030000000000bce1a40000000000000000000000000eb5ec7b";

        assertEq(Messages.formatAllowPoolCurrency(poolId, currency), expectedHex);

        (uint64 decodedPoolId, uint128 decodedCurrency) = Messages.parseAllowPoolCurrency(expectedHex.ref(0));
        assertEq(decodedPoolId, poolId);
        assertEq(uint256(decodedCurrency), currency);
    }

    function testAllowPoolCurrencyEquivalence(uint128 currency, uint64 poolId) public {
        bytes memory _message = Messages.formatAllowPoolCurrency(poolId, currency);
        (uint64 decodedPoolId, uint128 decodedCurrency) = Messages.parseAllowPoolCurrency(_message.ref(0));
        assertEq(uint256(decodedPoolId), uint256(poolId));
        assertEq(decodedCurrency, uint256(currency));
    }

    function testAddTranche() public {
        uint64 poolId = 1;
        bytes16 trancheId = bytes16(hex"811acd5b3f17c06841c7e41e9e04cb1b");
        string memory name = "Some Name";
        string memory symbol = "SYMBOL";
        uint8 decimals = 15;
        uint128 price = 1_000_000_000_000_000_000_000_000_000;
        bytes memory expectedHex =
            hex"040000000000000001811acd5b3f17c06841c7e41e9e04cb1b536f6d65204e616d65000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000053594d424f4c00000000000000000000000000000000000000000000000000000f00000000033b2e3c9fd0803ce8000000";

        assertEq(Messages.formatAddTranche(poolId, trancheId, name, symbol, decimals, price), expectedHex);

        (
            uint64 decodedPoolId,
            bytes16 decodedTrancheId,
            string memory decodedTokenName,
            string memory decodedTokenSymbol,
            uint8 decodedDecimals,
            uint128 decodedPrice
        ) = Messages.parseAddTranche(expectedHex.ref(0));

        assertEq(uint256(decodedPoolId), poolId);
        assertEq(decodedTrancheId, trancheId);
        assertEq(decodedTokenName, name);
        assertEq(decodedTokenSymbol, symbol);
        assertEq(decodedDecimals, decimals);
        assertEq(decodedPrice, price);
    }

    function testAddTrancheEquivalence(
        uint64 poolId,
        bytes16 trancheId,
        string memory tokenName,
        string memory tokenSymbol,
        uint8 decimals,
        uint128 price
    ) public {
        bytes memory _message = Messages.formatAddTranche(poolId, trancheId, tokenName, tokenSymbol, decimals, price);
        (
            uint64 decodedPoolId,
            bytes16 decodedTrancheId,
            string memory decodedTokenName,
            string memory decodedTokenSymbol,
            uint8 decodedDecimals,
            uint128 decodedPrice
        ) = Messages.parseAddTranche(_message.ref(0));
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

    function testUpdateTrancheTokenPrice() public {
        uint64 poolId = 1;
        bytes16 trancheId = bytes16(hex"811acd5b3f17c06841c7e41e9e04cb1b");
        uint128 price = 1_000_000_000_000_000_000_000_000_000;
        bytes memory expectedHex =
            hex"050000000000000001811acd5b3f17c06841c7e41e9e04cb1b00000000033b2e3c9fd0803ce8000000";

        assertEq(Messages.formatUpdateTrancheTokenPrice(poolId, trancheId, price), expectedHex);

        (uint64 decodedPoolId, bytes16 decodedTrancheId, uint128 decodedPrice) =
            Messages.parseUpdateTrancheTokenPrice(expectedHex.ref(0));
        assertEq(uint256(decodedPoolId), poolId);
        assertEq(decodedTrancheId, trancheId);
        assertEq(decodedPrice, price);
    }

    function testUpdateTrancheTokenPriceEquivalence(uint64 poolId, bytes16 trancheId, uint128 price) public {
        bytes memory _message = Messages.formatUpdateTrancheTokenPrice(poolId, trancheId, price);
        (uint64 decodedPoolId, bytes16 decodedTrancheId, uint128 decodedPrice) =
            Messages.parseUpdateTrancheTokenPrice(_message.ref(0));
        assertEq(uint256(decodedPoolId), uint256(poolId));
        assertEq(decodedTrancheId, trancheId);
        assertEq(uint256(decodedPrice), uint256(price));
    }

    // Note: UpdateMember encodes differently in Solidity compared to the Rust counterpart because `user` is a 20-byte
    // value in Solidity while it is 32-byte in Rust. However, UpdateMember messages coming from the cent-chain will
    // be handled correctly as the last 12 bytes out of said 32 will be ignored.
    function testUpdateMember() public {
        uint64 poolId = 2;
        bytes16 trancheId = bytes16(hex"811acd5b3f17c06841c7e41e9e04cb1b");
        bytes32 member = bytes32(0x4564564564564564564564564564564564564564564564564564564564564564);
        uint64 validUntil = 1706260138;
        bytes memory expectedHex =
            hex"060000000000000002811acd5b3f17c06841c7e41e9e04cb1b45645645645645645645645645645645645645645645645645645645645645640000000065b376aa";

        assertEq(Messages.formatUpdateMember(poolId, trancheId, member, validUntil), expectedHex);

        (uint64 decodedPoolId, bytes16 decodedTrancheId, address decodedMember, uint64 decodedValidUntil) =
            Messages.parseUpdateMember(expectedHex.ref(0));
        assertEq(uint256(decodedPoolId), poolId);
        assertEq(decodedTrancheId, trancheId);
        assertEq(decodedMember, address(bytes20(member)));
        assertEq(decodedValidUntil, validUntil);
    }

    function testUpdateMemberEquivalence(uint64 poolId, bytes16 trancheId, address user, uint64 validUntil) public {
        bytes memory _message = Messages.formatUpdateMember(poolId, trancheId, user, validUntil);
        (uint64 decodedPoolId, bytes16 decodedTrancheId, address decodedUser, uint64 decodedValidUntil) =
            Messages.parseUpdateMember(_message.ref(0));
        assertEq(uint256(decodedPoolId), uint256(poolId));
        assertEq(decodedTrancheId, trancheId);
        assertEq(decodedUser, user);
        assertEq(uint256(decodedValidUntil), uint256(validUntil));
    }

    function testTransfer() public {
        uint64 currency = 246803579;
        bytes32 sender = bytes32(0x4564564564564564564564564564564564564564564564564564564564564564);
        address receiver = 0x1231231231231231231231231231231231231231;
        uint128 amount = 100000000000000000000000000;
        bytes memory expectedHex =
            hex"070000000000000000000000000eb5ec7b45645645645645645645645645645645645645645645645645645645645645641231231231231231231231231231231231231231000000000000000000000000000000000052b7d2dcc80cd2e4000000";

        assertEq(Messages.formatTransfer(currency, sender, bytes32(bytes20(receiver)), amount), expectedHex);

        (uint128 decodedCurrency, bytes32 decodedSender, bytes32 decodedReceiver, uint128 decodedAmount) =
            Messages.parseTransfer(expectedHex.ref(0));
        assertEq(uint256(decodedCurrency), currency);
        assertEq(decodedSender, sender);
        assertEq(decodedReceiver, bytes32(bytes20(receiver)));
        assertEq(decodedAmount, amount);

        // Test the optimised `parseIncomingTransfer` now
        (uint128 decodedCurrency2, address decodedReceiver2, uint128 decodedAmount2) =
            Messages.parseIncomingTransfer(expectedHex.ref(0));
        assertEq(uint256(decodedCurrency2), currency);
        assertEq(decodedReceiver2, receiver);
        assertEq(decodedAmount2, amount);
    }

    function testTransferEquivalence(uint128 token, bytes32 sender, bytes32 receiver, uint128 amount) public {
        bytes memory _message = Messages.formatTransfer(token, sender, receiver, amount);
        (uint128 decodedToken, bytes32 decodedSender, bytes32 decodedReceiver, uint128 decodedAmount) =
            Messages.parseTransfer(_message.ref(0));
        assertEq(uint256(decodedToken), uint256(token));
        assertEq(decodedSender, sender);
        assertEq(decodedReceiver, receiver);
        assertEq(decodedAmount, amount);

        // Test the optimised `parseIncomingTransfer` now
        (uint128 decodedToken2, address decodedRecipient2, uint128 decodedAmount2) =
            Messages.parseIncomingTransfer(_message.ref(0));
        assertEq(uint256(decodedToken2), uint256(decodedToken));
        assertEq(decodedRecipient2, address(bytes20(decodedReceiver)));
        assertEq(decodedAmount, decodedAmount2);
    }

    function testTransferTrancheTokensToEvm() public {
        uint64 poolId = 1;
        bytes16 trancheId = bytes16(hex"811acd5b3f17c06841c7e41e9e04cb1b");
        bytes32 sender = bytes32(0x4564564564564564564564564564564564564564564564564564564564564564);
        bytes9 domain = Messages.formatDomain(Messages.Domain.EVM, 1284);
        address receiver = 0x1231231231231231231231231231231231231231;
        uint128 amount = 100000000000000000000000000;
        bytes memory expectedHex =
            hex"080000000000000001811acd5b3f17c06841c7e41e9e04cb1b45645645645645645645645645645645645645645645645645645645645645640100000000000005041231231231231231231231231231231231231231000000000000000000000000000000000052b7d2dcc80cd2e4000000";

        assertEq(Messages.formatTransferTrancheTokens(poolId, trancheId, sender, domain, receiver, amount), expectedHex);

        (uint64 decodedPoolId, bytes16 decodedTrancheId, address decodedReceiver, uint128 decodedAmount) =
            Messages.parseTransferTrancheTokens20(expectedHex.ref(0));
        assertEq(uint256(decodedPoolId), poolId);
        assertEq(decodedTrancheId, trancheId);
        assertEq(decodedReceiver, receiver);
        assertEq(decodedAmount, amount);
    }

    //TODO: fix stack issue
    // function testTransferTrancheTokensToCentrifuge() public {
    //     uint64 poolId = 1;
    //     bytes16 trancheId = bytes16(hex"811acd5b3f17c06841c7e41e9e04cb1b");
    //     address sender = 0x1231231231231231231231231231231231231231;
    //     bytes9 domain = Messages.formatDomain(Messages.Domain.Centrifuge);
    //     bytes32 receiver = bytes32(0x4564564564564564564564564564564564564564564564564564564564564564);
    //     uint128 amount = 100000000000000000000000000;
    //     uint128 currency = 1;
    //     bytes memory expectedHex =
    //         hex"080000000000000001811acd5b3f17c06841c7e41e9e04cb1b12312312312312312312312312312312312312310000000000000000000000000000000000000000004564564564564564564564564564564564564564564564564564564564564564000000000052b7d2dcc80cd2e4000000";

    //     assertEq(
    //         Messages.formatTransferTrancheTokens(
    //             poolId, trancheId, bytes32(bytes20(sender)), domain, currency, receiver, amount
    //         ),
    //         expectedHex
    //     );

    //     (
    //         uint64 decodedPoolId,
    //         bytes16 decodedTrancheId,
    //         bytes32 decodedSender,
    //         bytes9 decodedDomain,
    //         uint128 decodedCurrency,
    //         bytes32 decodedReceiver,
    //         uint128 decodedAmount
    //     ) = Messages.parseTransferTrancheTokens32(expectedHex.ref(0));
    //     assertEq(uint256(decodedPoolId), poolId);
    //     assertEq(decodedTrancheId, trancheId);
    //     assertEq(decodedSender, bytes32(bytes20(sender)));
    //     assertEq(decodedDomain, domain);
    //     assertEq(decodedCurrency, currency);
    //     assertEq(decodedReceiver, receiver);
    //     assertEq(decodedAmount, amount);
    // }

    function testTransferTrancheTokensToEvmEquivalence(
        uint64 poolId,
        bytes16 trancheId,
        bytes32 sender,
        uint64 destinationChainId,
        address destinationAddress,
        uint128 amount
    ) public {
        bytes memory _message = Messages.formatTransferTrancheTokens(
            poolId,
            trancheId,
            sender,
            Messages.formatDomain(Messages.Domain.EVM, destinationChainId),
            destinationAddress,
            amount
        );

        (uint64 decodedPoolId, bytes16 decodedTrancheId, address decodedDestinationAddress, uint256 decodedAmount) =
            Messages.parseTransferTrancheTokens20(_message.ref(0));
        assertEq(uint256(decodedPoolId), uint256(poolId));
        assertEq(decodedTrancheId, trancheId);
        assertEq(decodedDestinationAddress, destinationAddress);
        assertEq(decodedAmount, amount);
    }

    function testIncreaseInvestOrder() public {
        uint64 poolId = 1;
        bytes16 trancheId = bytes16(hex"811acd5b3f17c06841c7e41e9e04cb1b");
        bytes32 investor = bytes32(0x4564564564564564564564564564564564564564564564564564564564564564);
        uint128 currency = 246803579;
        uint128 amount = 100000000000000000000000000;
        bytes memory expectedHex =
            hex"090000000000000001811acd5b3f17c06841c7e41e9e04cb1b45645645645645645645645645645645645645645645645645645645645645640000000000000000000000000eb5ec7b000000000052b7d2dcc80cd2e4000000";

        assertEq(Messages.formatIncreaseInvestOrder(poolId, trancheId, investor, currency, amount), expectedHex);

        (
            uint64 decodedPoolId,
            bytes16 decodedTrancheId,
            bytes32 decodedInvestor,
            uint128 decodedCurrency,
            uint128 decodedAmount
        ) = Messages.parseIncreaseInvestOrder(expectedHex.ref(0));
        assertEq(uint256(decodedPoolId), poolId);
        assertEq(decodedTrancheId, trancheId);
        assertEq(decodedInvestor, investor);
        assertEq(decodedCurrency, currency);
        assertEq(decodedAmount, amount);
    }

    function testIncreaseInvestOrderEquivalence(
        uint64 poolId,
        bytes16 trancheId,
        bytes32 investor,
        uint128 token,
        uint128 amount
    ) public {
        bytes memory _message = Messages.formatIncreaseInvestOrder(poolId, trancheId, investor, token, amount);
        (
            uint64 decodedPoolId,
            bytes16 decodedTrancheId,
            bytes32 decodedInvestor,
            uint128 decodedToken,
            uint128 decodedAmount
        ) = Messages.parseIncreaseInvestOrder(_message.ref(0));

        assertEq(uint256(decodedPoolId), uint256(poolId));
        assertEq(decodedTrancheId, trancheId);
        assertEq(decodedInvestor, investor);
        assertEq(decodedToken, token);
        assertEq(decodedAmount, amount);
    }

    function testDecreaseInvestOrder() public {
        uint64 poolId = 1;
        bytes16 trancheId = bytes16(hex"811acd5b3f17c06841c7e41e9e04cb1b");
        bytes32 investor = bytes32(0x4564564564564564564564564564564564564564564564564564564564564564);
        uint128 currency = 246803579;
        uint128 amount = 100000000000000000000000000;
        bytes memory expectedHex =
            hex"0a0000000000000001811acd5b3f17c06841c7e41e9e04cb1b45645645645645645645645645645645645645645645645645645645645645640000000000000000000000000eb5ec7b000000000052b7d2dcc80cd2e4000000";

        assertEq(Messages.formatDecreaseInvestOrder(poolId, trancheId, investor, currency, amount), expectedHex);

        (
            uint64 decodedPoolId,
            bytes16 decodedTrancheId,
            bytes32 decodedInvestor,
            uint128 decodedCurrency,
            uint128 decodedAmount
        ) = Messages.parseDecreaseInvestOrder(expectedHex.ref(0));
        assertEq(uint256(decodedPoolId), poolId);
        assertEq(decodedTrancheId, trancheId);
        assertEq(decodedInvestor, investor);
        assertEq(decodedCurrency, currency);
        assertEq(decodedAmount, amount);
    }

    function testDecreaseInvestOrderEquivalence(
        uint64 poolId,
        bytes16 trancheId,
        bytes32 investor,
        uint128 token,
        uint128 amount
    ) public {
        bytes memory _message = Messages.formatDecreaseInvestOrder(poolId, trancheId, investor, token, amount);
        (
            uint64 decodedPoolId,
            bytes16 decodedTrancheId,
            bytes32 decodedInvestor,
            uint128 decodedToken,
            uint128 decodedAmount
        ) = Messages.parseDecreaseInvestOrder(_message.ref(0));

        assertEq(uint256(decodedPoolId), uint256(poolId));
        assertEq(decodedTrancheId, trancheId);
        assertEq(decodedInvestor, investor);
        assertEq(decodedToken, token);
        assertEq(decodedAmount, amount);
    }

    function testIncreaseRedeemOrder() public {
        uint64 poolId = 1;
        bytes16 trancheId = bytes16(hex"811acd5b3f17c06841c7e41e9e04cb1b");
        bytes32 investor = bytes32(0x4564564564564564564564564564564564564564564564564564564564564564);
        uint128 currency = 246803579;
        uint128 amount = 100000000000000000000000000;
        bytes memory expectedHex =
            hex"0b0000000000000001811acd5b3f17c06841c7e41e9e04cb1b45645645645645645645645645645645645645645645645645645645645645640000000000000000000000000eb5ec7b000000000052b7d2dcc80cd2e4000000";

        assertEq(Messages.formatIncreaseRedeemOrder(poolId, trancheId, investor, currency, amount), expectedHex);

        (
            uint64 decodedPoolId,
            bytes16 decodedTrancheId,
            bytes32 decodedInvestor,
            uint128 decodedCurrency,
            uint128 decodedAmount
        ) = Messages.parseIncreaseRedeemOrder(expectedHex.ref(0));
        assertEq(uint256(decodedPoolId), poolId);
        assertEq(decodedTrancheId, trancheId);
        assertEq(decodedInvestor, investor);
        assertEq(decodedCurrency, currency);
        assertEq(decodedAmount, amount);
    }

    function testIncreaseRedeemOrderEquivalence(
        uint64 poolId,
        bytes16 trancheId,
        bytes32 investor,
        uint128 token,
        uint128 amount
    ) public {
        bytes memory _message = Messages.formatIncreaseRedeemOrder(poolId, trancheId, investor, token, amount);
        (
            uint64 decodedPoolId,
            bytes16 decodedTrancheId,
            bytes32 decodedInvestor,
            uint128 decodedToken,
            uint128 decodedAmount
        ) = Messages.parseIncreaseRedeemOrder(_message.ref(0));

        assertEq(uint256(decodedPoolId), uint256(poolId));
        assertEq(decodedTrancheId, trancheId);
        assertEq(decodedInvestor, investor);
        assertEq(decodedToken, token);
        assertEq(decodedAmount, amount);
    }

    function testDecreaseRedeemOrder() public {
        uint64 poolId = 1;
        bytes16 trancheId = bytes16(hex"811acd5b3f17c06841c7e41e9e04cb1b");
        bytes32 investor = bytes32(0x4564564564564564564564564564564564564564564564564564564564564564);
        uint128 currency = 246803579;
        uint128 amount = 100000000000000000000000000;
        bytes memory expectedHex =
            hex"0c0000000000000001811acd5b3f17c06841c7e41e9e04cb1b45645645645645645645645645645645645645645645645645645645645645640000000000000000000000000eb5ec7b000000000052b7d2dcc80cd2e4000000";

        assertEq(Messages.formatDecreaseRedeemOrder(poolId, trancheId, investor, currency, amount), expectedHex);

        (
            uint64 decodedPoolId,
            bytes16 decodedTrancheId,
            bytes32 decodedInvestor,
            uint128 decodedCurrency,
            uint128 decodedAmount
        ) = Messages.parseDecreaseRedeemOrder(expectedHex.ref(0));
        assertEq(uint256(decodedPoolId), poolId);
        assertEq(decodedTrancheId, trancheId);
        assertEq(decodedInvestor, investor);
        assertEq(decodedCurrency, currency);
        assertEq(decodedAmount, amount);
    }

    function testDecreaseRedeemOrderEquivalence(
        uint64 poolId,
        bytes16 trancheId,
        bytes32 investor,
        uint128 token,
        uint128 amount
    ) public {
        bytes memory _message = Messages.formatDecreaseRedeemOrder(poolId, trancheId, investor, token, amount);
        (
            uint64 decodedPoolId,
            bytes16 decodedTrancheId,
            bytes32 decodedInvestor,
            uint128 decodedToken,
            uint128 decodedAmount
        ) = Messages.parseDecreaseRedeemOrder(_message.ref(0));

        assertEq(uint256(decodedPoolId), uint256(poolId));
        assertEq(decodedTrancheId, trancheId);
        assertEq(decodedInvestor, investor);
        assertEq(decodedToken, token);
        assertEq(decodedAmount, amount);
    }

    function testCollectInvest() public {
        uint64 poolId = 1;
        bytes16 trancheId = bytes16(hex"811acd5b3f17c06841c7e41e9e04cb1b");
        bytes32 investor = bytes32(0x4564564564564564564564564564564564564564564564564564564564564564);
        uint128 currency = 246803579;

        bytes memory expectedHex =
            hex"0d0000000000000001811acd5b3f17c06841c7e41e9e04cb1b45645645645645645645645645645645645645645645645645645645645645640000000000000000000000000eb5ec7b";

        assertEq(Messages.formatCollectInvest(poolId, trancheId, investor, currency), expectedHex);

        (uint64 decodedPoolId, bytes16 decodedTrancheId, bytes32 decodedInvestor, uint128 decodedCurrency) =
            Messages.parseCollectInvest(expectedHex.ref(0));
        assertEq(uint256(decodedPoolId), poolId);
        assertEq(decodedTrancheId, trancheId);
        assertEq(decodedInvestor, investor);
        assertEq(decodedCurrency, currency);
    }

    function testCollectInvestEquivalence(uint64 poolId, bytes16 trancheId, bytes32 user, uint128 currency) public {
        bytes memory _message = Messages.formatCollectInvest(poolId, trancheId, user, currency);
        (uint64 decodedPoolId, bytes16 decodedTrancheId, bytes32 decodedUser, uint128 decodedCurrency) =
            Messages.parseCollectInvest(_message.ref(0));

        assertEq(uint256(decodedPoolId), uint256(poolId));
        assertEq(decodedTrancheId, trancheId);
        assertEq(decodedUser, user);
        assertEq(decodedCurrency, currency);
    }

    function testCollectRedeem() public {
        uint64 poolId = 12378532;
        bytes16 trancheId = bytes16(hex"811acd5b3f17c06841c7e41e9e04cb1b");
        bytes32 investor = bytes32(0x4564564564564564564564564564564564564564564564564564564564564564);
        uint128 currency = 246803579;

        bytes memory expectedHex =
            hex"0e0000000000bce1a4811acd5b3f17c06841c7e41e9e04cb1b45645645645645645645645645645645645645645645645645645645645645640000000000000000000000000eb5ec7b";

        assertEq(Messages.formatCollectRedeem(poolId, trancheId, investor, currency), expectedHex);

        (uint64 decodedPoolId, bytes16 decodedTrancheId, bytes32 decodedInvestor, uint128 decodedCurrency) =
            Messages.parseCollectRedeem(expectedHex.ref(0));
        assertEq(uint256(decodedPoolId), poolId);
        assertEq(decodedTrancheId, trancheId);
        assertEq(decodedInvestor, investor);
        assertEq(decodedCurrency, currency);
    }

    function testCollectRedeemEquivalence(uint64 poolId, bytes16 trancheId, bytes32 user, uint128 currency) public {
        bytes memory _message = Messages.formatCollectRedeem(poolId, trancheId, user, currency);
        (uint64 decodedPoolId, bytes16 decodedTrancheId, bytes32 decodedUser, uint128 decodedCurrency) =
            Messages.parseCollectRedeem(_message.ref(0));

        assertEq(uint256(decodedPoolId), uint256(poolId));
        assertEq(decodedTrancheId, trancheId);
        assertEq(decodedUser, user);
        assertEq(decodedCurrency, currency);
    }

    function testExecutedDecreaseInvestOrder() public {
        uint64 poolId = 12378532;
        bytes16 trancheId = bytes16(hex"811acd5b3f17c06841c7e41e9e04cb1b");
        bytes32 investor = bytes32(0x1231231231231231231231231231231231231231000000000000000000000000);
        uint128 currency = 246803579;
        uint128 currencyPayout = 50000000000000000000000000;
        bytes memory expectedHex =
            hex"0f0000000000bce1a4811acd5b3f17c06841c7e41e9e04cb1b12312312312312312312312312312312312312310000000000000000000000000000000000000000000000000eb5ec7b0000000000295be96e64066972000000";

        assertEq(
            Messages.formatExecutedDecreaseInvestOrder(poolId, trancheId, investor, currency, currencyPayout),
            expectedHex
        );

        (
            uint64 decodedPoolId,
            bytes16 decodedTrancheId,
            address decodedInvestor,
            uint128 decodedCurrency,
            uint128 decodedCurrencyPayout
        ) = Messages.parseExecutedDecreaseInvestOrder(expectedHex.ref(0));
        assertEq(uint256(decodedPoolId), poolId);
        assertEq(decodedTrancheId, trancheId);
        assertEq(decodedInvestor, address(bytes20(investor)));
        assertEq(decodedCurrency, currency);
        assertEq(decodedCurrencyPayout, currencyPayout);
    }

    function testExecutedDecreaseInvestOrderEquivalence(
        uint64 poolId,
        bytes16 trancheId,
        bytes32 investor,
        uint128 currency,
        uint128 currencyPayout
    ) public {
        bytes memory _message =
            Messages.formatExecutedDecreaseInvestOrder(poolId, trancheId, investor, currency, currencyPayout);
        (
            uint64 decodedPoolId,
            bytes16 decodedTrancheId,
            address decodedInvestor,
            uint128 decodedCurrency,
            uint128 decodedCurrencyPayout
        ) = Messages.parseExecutedDecreaseInvestOrder(_message.ref(0));

        assertEq(uint256(decodedPoolId), uint256(poolId));
        assertEq(decodedTrancheId, trancheId);
        assertEq(decodedInvestor, address(bytes20(investor)));
        assertEq(decodedCurrency, currency);
        assertEq(decodedCurrencyPayout, currencyPayout);
    }

    function testExecutedDecreaseRedeemOrder() public {
        uint64 poolId = 12378532;
        bytes16 trancheId = bytes16(hex"811acd5b3f17c06841c7e41e9e04cb1b");
        bytes32 investor = bytes32(0x1231231231231231231231231231231231231231000000000000000000000000);
        uint128 currency = 246803579;
        uint128 currencyPayout = 50000000000000000000000000;

        bytes memory expectedHex =
            hex"100000000000bce1a4811acd5b3f17c06841c7e41e9e04cb1b12312312312312312312312312312312312312310000000000000000000000000000000000000000000000000eb5ec7b0000000000295be96e64066972000000";

        assertEq(
            Messages.formatExecutedDecreaseRedeemOrder(poolId, trancheId, investor, currency, currencyPayout),
            expectedHex
        );

        (
            uint64 decodedPoolId,
            bytes16 decodedTrancheId,
            address decodedInvestor,
            uint128 decodedCurrency,
            uint128 decodedCurrencyPayout
        ) = Messages.parseExecutedDecreaseRedeemOrder(expectedHex.ref(0));
        assertEq(uint256(decodedPoolId), poolId);
        assertEq(decodedTrancheId, trancheId);
        assertEq(bytes32(bytes20(decodedInvestor)), investor);
        assertEq(decodedCurrency, currency);
        assertEq(decodedCurrencyPayout, currencyPayout);
    }

    function testExecutedDecreaseRedeemOrderEquivalence(
        uint64 poolId,
        bytes16 trancheId,
        bytes32 investor,
        uint128 currency,
        uint128 currencyPayout
    ) public {
        bytes memory _message =
            Messages.formatExecutedDecreaseRedeemOrder(poolId, trancheId, investor, currency, currencyPayout);
        (
            uint64 decodedPoolId,
            bytes16 decodedTrancheId,
            address decodedInvestor,
            uint128 decodedCurrency,
            uint128 decodedCurrencyPayout
        ) = Messages.parseExecutedDecreaseRedeemOrder(_message.ref(0));

        assertEq(uint256(decodedPoolId), uint256(poolId));
        assertEq(decodedTrancheId, trancheId);
        assertEq(decodedInvestor, address(bytes20(investor)));
        assertEq(decodedCurrency, currency);
        assertEq(decodedCurrencyPayout, currencyPayout);
    }

    function testExecutedCollectInvest() public {
        uint64 poolId = 12378532;
        bytes16 trancheId = bytes16(hex"811acd5b3f17c06841c7e41e9e04cb1b");
        bytes32 investor = bytes32(0x1231231231231231231231231231231231231231000000000000000000000000);
        uint128 currency = 246803579;
        uint128 currencyPayout = 100000000000000000000000000;
        uint128 trancheTokensPayout = 50000000000000000000000000;

        bytes memory expectedHex =
            hex"110000000000bce1a4811acd5b3f17c06841c7e41e9e04cb1b12312312312312312312312312312312312312310000000000000000000000000000000000000000000000000eb5ec7b000000000052b7d2dcc80cd2e40000000000000000295be96e64066972000000";

        assertEq(
            Messages.formatExecutedCollectInvest(
                poolId, trancheId, investor, currency, currencyPayout, trancheTokensPayout
            ),
            expectedHex
        );
        // separate asserts into two functions to avoid stack too deep error
        testParseExecutedCollectInvestPart1(expectedHex, poolId, trancheId, investor, currency);
        testParseExecutedCollectInvestPart2(expectedHex, currencyPayout, trancheTokensPayout);
    }

    function testParseExecutedCollectInvestPart1(
        bytes memory expectedHex,
        uint64 poolId,
        bytes16 trancheId,
        bytes32 investor,
        uint128 currency
    ) internal {
        (uint64 decodedPoolId, bytes16 decodedTrancheId, address decodedInvestor, uint128 decodedCurrency,,) =
            Messages.parseExecutedCollectInvest(expectedHex.ref(0));

        assertEq(decodedPoolId, poolId);
        assertEq(decodedTrancheId, trancheId);
        assertEq(decodedInvestor, address(bytes20(investor)));
        assertEq(decodedCurrency, currency);
    }

    function testParseExecutedCollectInvestPart2(
        bytes memory expectedHex,
        uint128 currencyPayout,
        uint128 trancheTokensPayout
    ) internal {
        (,,,, uint128 decodedcurrencyPayout, uint128 decodedTrancheTokensPayout) =
            Messages.parseExecutedCollectInvest(expectedHex.ref(0));

        assertEq(decodedcurrencyPayout, currencyPayout);
        assertEq(decodedTrancheTokensPayout, trancheTokensPayout);
    }

    function testExecutedCollectInvestEquivalence(
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
        // separate asserts into two functions to avoid stack too deep error
        testParseExecutedCollectInvestPart1(_message, poolId, trancheId, investor, currency);
        testParseExecutedCollectInvestPart2(_message, currencyPayout, trancheTokensPayout);
    }

    function testExecutedCollectRedeem() public {
        uint64 poolId = 12378532;
        bytes16 trancheId = bytes16(hex"811acd5b3f17c06841c7e41e9e04cb1b");
        bytes32 investor = bytes32(0x1231231231231231231231231231231231231231000000000000000000000000);
        uint128 currency = 246803579;
        uint128 currencyPayout = 100000000000000000000000000;
        uint128 trancheTokensRedeemed = 50000000000000000000000000;

        bytes memory expectedHex =
            hex"120000000000bce1a4811acd5b3f17c06841c7e41e9e04cb1b12312312312312312312312312312312312312310000000000000000000000000000000000000000000000000eb5ec7b000000000052b7d2dcc80cd2e40000000000000000295be96e64066972000000";

        assertEq(
            Messages.formatExecutedCollectRedeem(
                poolId, trancheId, investor, currency, currencyPayout, trancheTokensRedeemed
            ),
            expectedHex
        );
        // separate asserts into two functions to avoid stack too deep error
        testParseExecutedCollectRedeemPart1(expectedHex, poolId, trancheId, investor, currency);
        testParseExecutedCollectRedeemPart2(expectedHex, currencyPayout, trancheTokensRedeemed);
    }

    function testExecutedCollectRedeemEquivalence(
        uint64 poolId,
        bytes16 trancheId,
        bytes32 investor,
        uint128 currency,
        uint128 currencyPayout,
        uint128 trancheTokensRedeemed
    ) public {
        bytes memory _message = Messages.formatExecutedCollectRedeem(
            poolId, trancheId, investor, currency, currencyPayout, trancheTokensRedeemed
        );
        // separate asserts into two functions to avoid stack too deep error
        testParseExecutedCollectRedeemPart1(_message, poolId, trancheId, investor, currency);
        testParseExecutedCollectRedeemPart2(_message, currencyPayout, trancheTokensRedeemed);
    }

    function testParseExecutedCollectRedeemPart1(
        bytes memory expectedHex,
        uint64 poolId,
        bytes16 trancheId,
        bytes32 investor,
        uint128 currency
    ) internal {
        (uint64 decodedPoolId, bytes16 decodedTrancheId, address decodedInvestor, uint128 decodedCurrency,,) =
            Messages.parseExecutedCollectRedeem(expectedHex.ref(0));

        assertEq(decodedPoolId, poolId);
        assertEq(decodedTrancheId, trancheId);

        assertEq(decodedInvestor, address(bytes20(investor)));
        assertEq(decodedCurrency, currency);
    }

    function testParseExecutedCollectRedeemPart2(
        bytes memory expectedHex,
        uint128 currencyPayout,
        uint128 trancheTokensRedeemed
    ) internal {
        (,,,, uint128 decodedCurrencyPayout, uint128 decodedTrancheTokensRedeemed) =
            Messages.parseExecutedCollectRedeem(expectedHex.ref(0));

        assertEq(decodedCurrencyPayout, currencyPayout);
        assertEq(decodedTrancheTokensRedeemed, trancheTokensRedeemed);
    }

    function testUpdateTrancheTokenMetadata() public {
        uint64 poolId = 1;
        bytes16 trancheId = bytes16(hex"811acd5b3f17c06841c7e41e9e04cb1b");
        string memory name = "Some Name";
        string memory symbol = "SYMBOL";
        bytes memory expectedHex =
            hex"040000000000000001811acd5b3f17c06841c7e41e9e04cb1b536f6d65204e616d65000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000053594d424f4c0000000000000000000000000000000000000000000000000000";

        assertEq(Messages.formatUpdateTrancheTokenMetadata(poolId, trancheId, name, symbol), expectedHex);

        (
            uint64 decodedPoolId,
            bytes16 decodedTrancheId,
            string memory decodedTokenName,
            string memory decodedTokenSymbol
        ) = Messages.parseUpdateTrancheTokenMetadata(expectedHex.ref(0));

        assertEq(uint256(decodedPoolId), poolId);
        assertEq(decodedTrancheId, trancheId);
        assertEq(decodedTokenName, name);
        assertEq(decodedTokenSymbol, symbol);
    }

    function testUpdateTrancheTokenMetadataEquivalence(
        uint64 poolId,
        bytes16 trancheId,
        string memory tokenName,
        string memory tokenSymbol
    ) public {
        bytes memory _message = Messages.formatUpdateTrancheTokenMetadata(poolId, trancheId, tokenName, tokenSymbol);
        (
            uint64 decodedPoolId,
            bytes16 decodedTrancheId,
            string memory decodedTokenName,
            string memory decodedTokenSymbol
        ) = Messages.parseUpdateTrancheTokenMetadata(_message.ref(0));
        assertEq(uint256(decodedPoolId), uint256(poolId));
        assertEq(decodedTrancheId, trancheId);
        // Comparing raw input to output can erroneously fail when a byte string is given.
        // Intended behaviour is that byte strings will be treated as bytes and converted to strings instead
        // of treated as strings themselves. This conversion from string to bytes32 to string is used to simulate
        // this intended behaviour.
        assertEq(decodedTokenName, bytes32ToString(stringToBytes32(tokenName)));
        assertEq(decodedTokenSymbol, bytes32ToString(stringToBytes32(tokenSymbol)));
    }

    function testFormatDomainCentrifuge() public {
        assertEq(Messages.formatDomain(Messages.Domain.Centrifuge), hex"000000000000000000");
    }

    function testFormatDomainMoonbeam() public {
        assertEq(Messages.formatDomain(Messages.Domain.EVM, 1284), hex"010000000000000504");
    }

    function testFormatDomainMoonbaseAlpha() public {
        assertEq(Messages.formatDomain(Messages.Domain.EVM, 1287), hex"010000000000000507");
    }

    function testFormatDomainAvalanche() public {
        assertEq(Messages.formatDomain(Messages.Domain.EVM, 43114), hex"01000000000000a86a");
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
