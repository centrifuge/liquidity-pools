// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import {MessagesLib} from "src/libraries/MessagesLib.sol";
import {CastLib} from "src/libraries/CastLib.sol";
import "forge-std/Test.sol";

contract MessagesLibTest is Test {
    using CastLib for *;

    function setUp() public {}

    function testAddCurrency() public {
        uint128 currency = 246803579;
        address currencyAddress = 0x1231231231231231231231231231231231231231;
        bytes memory expectedHex = hex"010000000000000000000000000eb5ec7b1231231231231231231231231231231231231231";

        assertEq(abi.encodePacked(uint8(MessagesLib.Call.AddCurrency), currency, currencyAddress), expectedHex);

        (uint128 decodedCurrency, address decodedCurrencyAddress) = MessagesLib.parseAddCurrency(expectedHex);
        assertEq(uint256(decodedCurrency), currency);
        assertEq(decodedCurrencyAddress, currencyAddress);
    }

    function testAddPool() public {
        uint64 poolId = 12378532;
        bytes memory expectedHex = hex"020000000000bce1a4";

        assertEq(abi.encodePacked(uint8(MessagesLib.Call.AddPool), poolId), expectedHex);

        (uint64 decodedPoolId) = MessagesLib.parseAddPool(expectedHex);
        assertEq(uint256(decodedPoolId), poolId);
    }

    function testAllowInvestmentCurrency() public {
        uint64 poolId = 12378532;
        uint128 currency = 246803579;
        bytes memory expectedHex = hex"030000000000bce1a40000000000000000000000000eb5ec7b";

        assertEq(abi.encodePacked(uint8(MessagesLib.Call.AllowInvestmentCurrency), poolId, currency), expectedHex);

        (uint64 decodedPoolId, uint128 decodedCurrency) = MessagesLib.parseAllowInvestmentCurrency(expectedHex);
        assertEq(decodedPoolId, poolId);
        assertEq(uint256(decodedCurrency), currency);
    }

    function testAddTranche() public {
        uint64 poolId = 1;
        bytes16 trancheId = bytes16(hex"811acd5b3f17c06841c7e41e9e04cb1b");
        string memory tokenName = "Some Name";
        string memory tokenSymbol = "SYMBOL";
        uint8 decimals = 15;
        uint8 restrictionSet = 2;
        bytes memory expectedHex =
            hex"040000000000000001811acd5b3f17c06841c7e41e9e04cb1b536f6d65204e616d65000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000053594d424f4c00000000000000000000000000000000000000000000000000000f02";

        assertEq(
            abi.encodePacked(
                uint8(MessagesLib.Call.AddTranche),
                poolId,
                trancheId,
                tokenName.toBytes128(),
                tokenSymbol.toBytes32(),
                decimals,
                restrictionSet
            ),
            expectedHex
        );

        (
            uint64 decodedPoolId,
            bytes16 decodedTrancheId,
            string memory decodedTokenName,
            string memory decodedTokenSymbol,
            uint8 decodedDecimals,
            uint8 decodedRestrictionSet
        ) = MessagesLib.parseAddTranche(expectedHex);

        assertEq(uint256(decodedPoolId), poolId);
        assertEq(decodedTrancheId, trancheId);
        assertEq(decodedTokenName, tokenName);
        assertEq(decodedTokenSymbol, tokenSymbol);
        assertEq(decodedDecimals, decimals);
        assertEq(decodedRestrictionSet, restrictionSet);
    }

    function testUpdateTrancheTokenPrice() public {
        uint64 poolId = 1;
        bytes16 trancheId = bytes16(hex"811acd5b3f17c06841c7e41e9e04cb1b");
        uint128 currencyId = 2;
        uint128 price = 1_000_000_000_000_000_000_000_000_000;
        uint64 computedAt = uint64(block.timestamp);
        bytes memory expectedHex =
            hex"050000000000000001811acd5b3f17c06841c7e41e9e04cb1b0000000000000000000000000000000200000000033b2e3c9fd0803ce80000000000000000000001";

        assertEq(
            abi.encodePacked(
                uint8(MessagesLib.Call.UpdateTrancheTokenPrice), poolId, trancheId, currencyId, price, computedAt
            ),
            expectedHex
        );

        (
            uint64 decodedPoolId,
            bytes16 decodedTrancheId,
            uint128 decodedCurrencyId,
            uint128 decodedPrice,
            uint64 decodedComputedAt
        ) = MessagesLib.parseUpdateTrancheTokenPrice(expectedHex);
        assertEq(uint256(decodedPoolId), poolId);
        assertEq(decodedTrancheId, trancheId);
        assertEq(decodedCurrencyId, currencyId);
        assertEq(decodedPrice, price);
        assertEq(decodedComputedAt, computedAt);
    }

    // Note: UpdateMember encodes differently in Solidity compared to the Rust counterpart
    // because `user` is a 20-byte value in Solidity while it is 32-byte in Rust.
    // However, UpdateMember messages coming from the cent-chain will
    // be handled correctly as the last 12 bytes out of said 32 will be ignored.
    function testUpdateMember() public {
        uint64 poolId = 2;
        bytes16 trancheId = bytes16(hex"811acd5b3f17c06841c7e41e9e04cb1b");
        bytes32 member = bytes32(0x4564564564564564564564564564564564564564564564564564564564564564);
        uint64 validUntil = 1706260138;
        bytes memory expectedHex =
            hex"060000000000000002811acd5b3f17c06841c7e41e9e04cb1b45645645645645645645645645645645645645645645645645645645645645640000000065b376aa";

        assertEq(
            abi.encodePacked(uint8(MessagesLib.Call.UpdateMember), poolId, trancheId, member, validUntil), expectedHex
        );

        (uint64 decodedPoolId, bytes16 decodedTrancheId, address decodedMember, uint64 decodedValidUntil) =
            MessagesLib.parseUpdateMember(expectedHex);
        assertEq(uint256(decodedPoolId), poolId);
        assertEq(decodedTrancheId, trancheId);
        assertEq(decodedMember, address(bytes20(member)));
        assertEq(decodedValidUntil, validUntil);
    }

    // function testTransfer() public {
    //     uint64 currency = 246803579;
    //     bytes32 sender = bytes32(0x4564564564564564564564564564564564564564564564564564564564564564);
    //     address receiver = 0x1231231231231231231231231231231231231231;
    //     uint128 amount = 100000000000000000000000000;
    //     bytes memory expectedHex =
    //         hex"070000000000000000000000000eb5ec7b45645645645645645645645645645645645645645645645645645645645645641231231231231231231231231231231231231231000000000000000000000000000000000052b7d2dcc80cd2e4000000";

    //     assertEq(
    //         abi.encodePacked(uint8(MessagesLib.Call.Transfer), currency, sender, receiver.toBytes32(), amount),
    //         expectedHex
    //     );

    //     (uint128 decodedCurrency, bytes32 decodedSender, bytes32 decodedReceiver, uint128 decodedAmount) =
    //         MessagesLib.parseTransfer(expectedHex);
    //     assertEq(uint256(decodedCurrency), currency);
    //     assertEq(decodedSender, sender);
    //     assertEq(decodedReceiver, bytes32(bytes20(receiver)));
    //     assertEq(decodedAmount, amount);

    //     // Test the optimised `parseIncomingTransfer` now
    //     (uint128 decodedCurrency2, address decodedReceiver2, uint128 decodedAmount2) =
    //         MessagesLib.parseIncomingTransfer(expectedHex);
    //     assertEq(uint256(decodedCurrency2), currency);
    //     assertEq(decodedReceiver2, receiver);
    //     assertEq(decodedAmount2, amount);
    // }

    function testTransferTrancheTokensToEvm() public {
        uint64 poolId = 1;
        bytes16 trancheId = bytes16(hex"811acd5b3f17c06841c7e41e9e04cb1b");
        bytes32 sender = bytes32(0x4564564564564564564564564564564564564564564564564564564564564564);
        bytes9 domain = MessagesLib.formatDomain(MessagesLib.Domain.EVM, 1284);
        address receiver = 0x1231231231231231231231231231231231231231;
        uint128 amount = 100000000000000000000000000;
        bytes memory expectedHex =
            hex"080000000000000001811acd5b3f17c06841c7e41e9e04cb1b45645645645645645645645645645645645645645645645645645645645645640100000000000005041231231231231231231231231231231231231231000000000000000000000000000000000052b7d2dcc80cd2e4000000";

        assertEq(
            abi.encodePacked(
                uint8(MessagesLib.Call.TransferTrancheTokens),
                poolId,
                trancheId,
                sender,
                domain,
                receiver.toBytes32(),
                amount
            ),
            expectedHex
        );

        (uint64 decodedPoolId, bytes16 decodedTrancheId, address decodedReceiver, uint128 decodedAmount) =
            MessagesLib.parseTransferTrancheTokens20(expectedHex);
        assertEq(uint256(decodedPoolId), poolId);
        assertEq(decodedTrancheId, trancheId);
        assertEq(decodedReceiver, receiver);
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

        assertEq(
            abi.encodePacked(uint8(MessagesLib.Call.IncreaseInvestOrder), poolId, trancheId, investor, currency, amount),
            expectedHex
        );

        (
            uint64 decodedPoolId,
            bytes16 decodedTrancheId,
            bytes32 decodedInvestor,
            uint128 decodedCurrency,
            uint128 decodedAmount
        ) = MessagesLib.parseIncreaseInvestOrder(expectedHex);
        assertEq(uint256(decodedPoolId), poolId);
        assertEq(decodedTrancheId, trancheId);
        assertEq(decodedInvestor, investor);
        assertEq(decodedCurrency, currency);
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

        assertEq(
            abi.encodePacked(uint8(MessagesLib.Call.IncreaseRedeemOrder), poolId, trancheId, investor, currency, amount),
            expectedHex
        );

        (
            uint64 decodedPoolId,
            bytes16 decodedTrancheId,
            bytes32 decodedInvestor,
            uint128 decodedCurrency,
            uint128 decodedAmount
        ) = MessagesLib.parseIncreaseRedeemOrder(expectedHex);
        assertEq(uint256(decodedPoolId), poolId);
        assertEq(decodedTrancheId, trancheId);
        assertEq(decodedInvestor, investor);
        assertEq(decodedCurrency, currency);
        assertEq(decodedAmount, amount);
    }

    function testExecutedDecreaseInvestOrder() public {
        uint64 poolId = 12378532;
        bytes16 trancheId = bytes16(hex"811acd5b3f17c06841c7e41e9e04cb1b");
        bytes32 investor = bytes32(0x1231231231231231231231231231231231231231000000000000000000000000);
        uint128 currency = 246803579;
        uint128 currencyPayout = 50000000000000000000000000;
        uint128 remainingInvestOrder = 5000000000000000000000000;
        bytes memory expectedHex =
            hex"0f0000000000bce1a4811acd5b3f17c06841c7e41e9e04cb1b12312312312312312312312312312312312312310000000000000000000000000000000000000000000000000eb5ec7b0000000000295be96e6406697200000000000000000422ca8b0a00a425000000";

        assertEq(
            abi.encodePacked(
                uint8(MessagesLib.Call.ExecutedDecreaseInvestOrder),
                poolId,
                trancheId,
                investor,
                currency,
                currencyPayout,
                remainingInvestOrder
            ),
            expectedHex
        );

        (
            uint64 decodedPoolId,
            bytes16 decodedTrancheId,
            address decodedInvestor,
            uint128 decodedCurrency,
            uint128 decodedCurrencyPayout,
            uint128 decodedRemainingInvestOrder
        ) = MessagesLib.parseExecutedDecreaseInvestOrder(expectedHex);
        assertEq(uint256(decodedPoolId), poolId);
        assertEq(decodedTrancheId, trancheId);
        assertEq(decodedInvestor, address(bytes20(investor)));
        assertEq(decodedCurrency, currency);
        assertEq(decodedCurrencyPayout, currencyPayout);
        assertEq(decodedRemainingInvestOrder, remainingInvestOrder);
    }

    function testExecutedDecreaseRedeemOrder() public {
        uint64 poolId = 12378532;
        bytes16 trancheId = bytes16(hex"811acd5b3f17c06841c7e41e9e04cb1b");
        bytes32 investor = bytes32(0x1231231231231231231231231231231231231231000000000000000000000000);
        uint128 currency = 246803579;
        uint128 trancheTokensPayout = 50000000000000000000000000;
        uint128 remainingRedeemOrder = 5000000000000000000000000;

        bytes memory expectedHex =
            hex"100000000000bce1a4811acd5b3f17c06841c7e41e9e04cb1b12312312312312312312312312312312312312310000000000000000000000000000000000000000000000000eb5ec7b0000000000295be96e6406697200000000000000000422ca8b0a00a425000000";

        assertEq(
            abi.encodePacked(
                uint8(MessagesLib.Call.ExecutedDecreaseRedeemOrder),
                poolId,
                trancheId,
                investor,
                currency,
                trancheTokensPayout,
                remainingRedeemOrder
            ),
            expectedHex
        );

        (
            uint64 decodedPoolId,
            bytes16 decodedTrancheId,
            address decodedInvestor,
            uint128 decodedCurrency,
            uint128 decodedTrancheTokensPayout,
            uint128 decodedRemainingRedeemOrder
        ) = MessagesLib.parseExecutedDecreaseRedeemOrder(expectedHex);
        assertEq(uint256(decodedPoolId), poolId);
        assertEq(decodedTrancheId, trancheId);
        assertEq(bytes32(bytes20(decodedInvestor)), investor);
        assertEq(decodedCurrency, currency);
        assertEq(decodedTrancheTokensPayout, trancheTokensPayout);
        assertEq(decodedRemainingRedeemOrder, remainingRedeemOrder);
    }

    function testExecutedCollectInvest() public {
        uint64 poolId = 12378532;
        bytes16 trancheId = bytes16(hex"811acd5b3f17c06841c7e41e9e04cb1b");
        bytes32 investor = bytes32(0x1231231231231231231231231231231231231231000000000000000000000000);
        uint128 currency = 246803579;
        uint128 currencyPayout = 100000000000000000000000000;
        uint128 trancheTokensPayout = 50000000000000000000000000;
        uint128 remainingInvestOrder = 5000000000000000000000000;

        bytes memory expectedHex =
            hex"110000000000bce1a4811acd5b3f17c06841c7e41e9e04cb1b12312312312312312312312312312312312312310000000000000000000000000000000000000000000000000eb5ec7b000000000052b7d2dcc80cd2e40000000000000000295be96e6406697200000000000000000422ca8b0a00a425000000";

        assertEq(
            abi.encodePacked(
                uint8(MessagesLib.Call.ExecutedCollectInvest),
                poolId,
                trancheId,
                investor,
                currency,
                currencyPayout,
                trancheTokensPayout,
                remainingInvestOrder
            ),
            expectedHex
        );
        // separate asserts into two functions to avoid stack too deep error
        testParseExecutedCollectInvestPart1(expectedHex, poolId, trancheId, investor, currency);
        testParseExecutedCollectInvestPart2(expectedHex, currencyPayout, trancheTokensPayout, remainingInvestOrder);
    }

    function testParseExecutedCollectInvestPart1(
        bytes memory expectedHex,
        uint64 poolId,
        bytes16 trancheId,
        bytes32 investor,
        uint128 currency
    ) internal {
        (uint64 decodedPoolId, bytes16 decodedTrancheId, address decodedInvestor, uint128 decodedCurrency,,,) =
            MessagesLib.parseExecutedCollectInvest(expectedHex);

        assertEq(decodedPoolId, poolId);
        assertEq(decodedTrancheId, trancheId);
        assertEq(decodedInvestor, address(bytes20(investor)));
        assertEq(decodedCurrency, currency);
    }

    function testParseExecutedCollectInvestPart2(
        bytes memory expectedHex,
        uint128 currencyPayout,
        uint128 trancheTokensPayout,
        uint128 remainingInvestOrder
    ) internal {
        (,,,, uint128 decodedcurrencyPayout, uint128 decodedTrancheTokensPayout, uint128 decodedRemainingInvestOrder) =
            MessagesLib.parseExecutedCollectInvest(expectedHex);

        assertEq(decodedcurrencyPayout, currencyPayout);
        assertEq(decodedTrancheTokensPayout, trancheTokensPayout);
        assertEq(decodedRemainingInvestOrder, remainingInvestOrder);
    }

    function testExecutedCollectRedeem() public {
        uint64 poolId = 12378532;
        bytes16 trancheId = bytes16(hex"811acd5b3f17c06841c7e41e9e04cb1b");
        bytes32 investor = bytes32(0x1231231231231231231231231231231231231231000000000000000000000000);
        uint128 currency = 246803579;
        uint128 currencyPayout = 100000000000000000000000000;
        uint128 trancheTokensPayout = 50000000000000000000000000;
        uint128 remainingRedeemOrder = 5000000000000000000000000;

        bytes memory expectedHex =
            hex"120000000000bce1a4811acd5b3f17c06841c7e41e9e04cb1b12312312312312312312312312312312312312310000000000000000000000000000000000000000000000000eb5ec7b000000000052b7d2dcc80cd2e40000000000000000295be96e6406697200000000000000000422ca8b0a00a425000000";

        assertEq(
            abi.encodePacked(
                uint8(MessagesLib.Call.ExecutedCollectRedeem),
                poolId,
                trancheId,
                investor,
                currency,
                currencyPayout,
                trancheTokensPayout,
                remainingRedeemOrder
            ),
            expectedHex
        );
        // separate asserts into two functions to avoid stack too deep error
        testParseExecutedCollectRedeemPart1(expectedHex, poolId, trancheId, investor, currency);
        testParseExecutedCollectRedeemPart2(expectedHex, currencyPayout, trancheTokensPayout, remainingRedeemOrder);
    }

    function testParseExecutedCollectRedeemPart1(
        bytes memory expectedHex,
        uint64 poolId,
        bytes16 trancheId,
        bytes32 investor,
        uint128 currency
    ) internal {
        (uint64 decodedPoolId, bytes16 decodedTrancheId, address decodedInvestor, uint128 decodedCurrency,,,) =
            MessagesLib.parseExecutedCollectRedeem(expectedHex);

        assertEq(decodedPoolId, poolId);
        assertEq(decodedTrancheId, trancheId);

        assertEq(decodedInvestor, address(bytes20(investor)));
        assertEq(decodedCurrency, currency);
    }

    function testParseExecutedCollectRedeemPart2(
        bytes memory expectedHex,
        uint128 currencyPayout,
        uint128 trancheTokensPayout,
        uint128 remainingRedeemOrder
    ) internal {
        (,,,, uint128 decodedCurrencyPayout, uint128 decodedtrancheTokensPayout, uint128 decodedRemainingRedeemOrder) =
            MessagesLib.parseExecutedCollectRedeem(expectedHex);

        assertEq(decodedCurrencyPayout, currencyPayout);
        assertEq(decodedtrancheTokensPayout, trancheTokensPayout);
        assertEq(decodedRemainingRedeemOrder, remainingRedeemOrder);
    }

    function testUpdateTrancheTokenMetadata() public {
        uint64 poolId = 1;
        bytes16 trancheId = bytes16(hex"811acd5b3f17c06841c7e41e9e04cb1b");
        string memory tokenName = "Some Name";
        string memory tokenSymbol = "SYMBOL";
        bytes memory expectedHex =
            hex"170000000000000001811acd5b3f17c06841c7e41e9e04cb1b536f6d65204e616d65000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000053594d424f4c0000000000000000000000000000000000000000000000000000";

        assertEq(
            abi.encodePacked(
                uint8(MessagesLib.Call.UpdateTrancheTokenMetadata),
                poolId,
                trancheId,
                tokenName.toBytes128(),
                tokenSymbol.toBytes32()
            ),
            expectedHex
        );

        (
            uint64 decodedPoolId,
            bytes16 decodedTrancheId,
            string memory decodedTokenName,
            string memory decodedTokenSymbol
        ) = MessagesLib.parseUpdateTrancheTokenMetadata(expectedHex);

        assertEq(uint256(decodedPoolId), poolId);
        assertEq(decodedTrancheId, trancheId);
        assertEq(decodedTokenName, tokenName);
        assertEq(decodedTokenSymbol, tokenSymbol);
    }

    function testCancelInvestOrder() public {
        uint64 poolId = 12378532;
        bytes16 trancheId = bytes16(hex"811acd5b3f17c06841c7e41e9e04cb1b");
        bytes32 investor = bytes32(0x1231231231231231231231231231231231231231000000000000000000000000);
        uint128 currency = 246803579;
        bytes memory expectedHex =
            hex"130000000000bce1a4811acd5b3f17c06841c7e41e9e04cb1b12312312312312312312312312312312312312310000000000000000000000000000000000000000000000000eb5ec7b";

        assertEq(
            abi.encodePacked(uint8(MessagesLib.Call.CancelInvestOrder), poolId, trancheId, investor, currency),
            expectedHex
        );

        (uint64 decodedPoolId, bytes16 decodedTrancheId, address decodedInvestor, uint128 decodedCurrency) =
            MessagesLib.parseCancelInvestOrder(expectedHex);
        assertEq(uint256(decodedPoolId), poolId);
        assertEq(decodedTrancheId, trancheId);
        assertEq(decodedInvestor, address(bytes20(investor)));
        assertEq(decodedCurrency, currency);
    }

    function testCancelRedeemOrder() public {
        uint64 poolId = 12378532;
        bytes16 trancheId = bytes16(hex"811acd5b3f17c06841c7e41e9e04cb1b");
        bytes32 investor = bytes32(0x1231231231231231231231231231231231231231000000000000000000000000);
        uint128 currency = 246803579;
        bytes memory expectedHex =
            hex"140000000000bce1a4811acd5b3f17c06841c7e41e9e04cb1b12312312312312312312312312312312312312310000000000000000000000000000000000000000000000000eb5ec7b";

        assertEq(
            abi.encodePacked(uint8(MessagesLib.Call.CancelRedeemOrder), poolId, trancheId, investor, currency),
            expectedHex
        );

        (uint64 decodedPoolId, bytes16 decodedTrancheId, address decodedInvestor, uint128 decodedCurrency) =
            MessagesLib.parseCancelRedeemOrder(expectedHex);
        assertEq(uint256(decodedPoolId), poolId);
        assertEq(decodedTrancheId, trancheId);
        assertEq(decodedInvestor, address(bytes20(investor)));
        assertEq(decodedCurrency, currency);
    }

    function testTriggerIncreaseRedeemOrder() public {
        uint64 poolId = 1;
        bytes16 trancheId = bytes16(hex"811acd5b3f17c06841c7e41e9e04cb1b");
        bytes32 investor = bytes32(0x1231231231231231231231231231231231231231000000000000000000000000);
        uint128 currency = 246803579;
        uint128 amount = 100000000000000000000000000;
        bytes memory expectedHex =
            hex"1b0000000000000001811acd5b3f17c06841c7e41e9e04cb1b12312312312312312312312312312312312312310000000000000000000000000000000000000000000000000eb5ec7b000000000052b7d2dcc80cd2e4000000";

        assertEq(
            abi.encodePacked(
                uint8(MessagesLib.Call.TriggerIncreaseRedeemOrder), poolId, trancheId, investor, currency, amount
            ),
            expectedHex
        );

        (
            uint64 decodedPoolId,
            bytes16 decodedTrancheId,
            address decodedInvestor,
            uint128 decodedCurrency,
            uint128 decodedAmount
        ) = MessagesLib.parseTriggerIncreaseRedeemOrder(expectedHex);
        assertEq(uint256(decodedPoolId), poolId);
        assertEq(decodedTrancheId, trancheId);
        assertEq(decodedInvestor, address(bytes20(investor)));
        assertEq(decodedCurrency, currency);
        assertEq(decodedAmount, amount);
    }

    function testFreeze() public {
        uint64 poolId = 2;
        bytes16 trancheId = bytes16(hex"811acd5b3f17c06841c7e41e9e04cb1b");
        address investor = 0x1231231231231231231231231231231231231231;
        bytes memory expectedHex =
            hex"190000000000000002811acd5b3f17c06841c7e41e9e04cb1b1231231231231231231231231231231231231231000000000000000000000000";

        assertEq(abi.encodePacked(uint8(MessagesLib.Call.Freeze), poolId, trancheId, investor.toBytes32()), expectedHex);

        (uint64 decodedPoolId, bytes16 decodedTrancheId, address decodedInvestor) = MessagesLib.parseFreeze(expectedHex);
        assertEq(uint256(decodedPoolId), poolId);
        assertEq(decodedTrancheId, trancheId);
        assertEq(decodedInvestor, investor);
    }

    function testDisallowInvestmentCurrency() public {
        uint64 poolId = 12378532;
        uint128 currency = 246803579;
        bytes memory expectedHex = hex"180000000000bce1a40000000000000000000000000eb5ec7b";

        assertEq(abi.encodePacked(uint8(MessagesLib.Call.DisallowInvestmentCurrency), poolId, currency), expectedHex);

        (uint64 decodedPoolId, uint128 decodedCurrency) = MessagesLib.parseDisallowInvestmentCurrency(expectedHex);
        assertEq(decodedPoolId, poolId);
        assertEq(uint256(decodedCurrency), currency);
    }

    function testMessageProof() public {
        uint64 poolId = 1;
        bytes memory payload = abi.encodePacked(uint8(MessagesLib.Call.AddPool), poolId);
        bytes memory expectedHex = hex"1cfe5c5905ed051500f0e9887c795a77399087aa6cbcbf48b19a9d162ba1b7fa76";

        assertEq(abi.encodePacked(uint8(MessagesLib.Call.MessageProof), keccak256(payload)), expectedHex);

        (bytes32 decodedProof) = MessagesLib.parseMessageProof(expectedHex);
        assertEq(decodedProof, keccak256(payload));
    }

    function testFormatDomainCentrifuge() public {
        assertEq(MessagesLib.formatDomain(MessagesLib.Domain.Centrifuge), hex"000000000000000000");
    }

    function testFormatDomainMoonbeam() public {
        assertEq(MessagesLib.formatDomain(MessagesLib.Domain.EVM, 1284), hex"010000000000000504");
    }

    function testFormatDomainMoonbaseAlpha() public {
        assertEq(MessagesLib.formatDomain(MessagesLib.Domain.EVM, 1287), hex"010000000000000507");
    }

    function testFormatDomainAvalanche() public {
        assertEq(MessagesLib.formatDomain(MessagesLib.Domain.EVM, 43114), hex"01000000000000a86a");
    }
}
