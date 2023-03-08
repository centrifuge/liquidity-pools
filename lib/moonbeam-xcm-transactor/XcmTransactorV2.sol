// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.7.6;
pragma abicoder v2;

// The XcmTransactorV2 contract's address.
address constant XCM_TRANSACTOR_V2_ADDRESS = 0x000000000000000000000000000000000000080D;

// The XcmTransactorV2 contract's instance.
XcmTransactorV2 constant XCM_TRANSACTOR_V2_CONTRACT = XcmTransactorV2(
    XCM_TRANSACTOR_V2_ADDRESS
);

// A multilocation is defined by its number of parents and the encoded junctions (interior)
struct Multilocation {
    uint8 parents;
    bytes[] interior;
}

// _author The Moonbeam Team
// _title Xcm Transactor Interface
// The interface through which solidity contracts will interact with xcm transactor pallet
// _custom:address 0x000000000000000000000000000000000000080D
interface XcmTransactorV2 {


    // Get index of an account in xcm transactor
    // _custom:selector 3fdc4f36
    // _param index The index of which we want to retrieve the account
    // _return owner The owner of the derivative index
    //
    function indexToAccount(uint16 index) external view returns (address owner);

    // Get transact info of a multilocation
    // _custom:selector b689e20c
    // _param multilocation The location for which we want to know the transact info
    // _return transactExtraWeight The extra weight involved in the XCM message of using derivative
    // _return transactExtraWeightSigned The extra weight involved in the XCM message of using signed
    // _return maxWeight Maximum allowed weight for a single message in dest
    //
    function transactInfoWithSigned(Multilocation memory multilocation)
        external
        view
        returns (
            uint64 transactExtraWeight,
            uint64 transactExtraWeightSigned,
            uint64 maxWeight
        );

    // Get fee per second charged in its reserve chain for an asset
    // _custom:selector 906c9990
    // _param multilocation The asset location for which we want to know the fee per second value
    // _return feePerSecond The fee per second that the reserve chain charges for this asset
    //
    function feePerSecond(Multilocation memory multilocation)
        external
        view
        returns (uint256 feePerSecond);

    // Transact through XCM using fee based on its multilocation
    // _custom:selector fe430475
    // _dev The token transfer burns/transfers the corresponding amount before sending
    // _param transactor The transactor to be used
    // _param index The index to be used
    // _param feeAsset The asset in which we want to pay fees.
    // It has to be a reserve of the destination chain
    // _param transactRequiredWeightAtMost The weight we want to buy in the destination chain
    // _param innerCall The inner call to be executed in the destination chain
    // _param feeAmount Amount to be used as fee.
    // _param overallWeight Overall weight to be used for the xcm message.
    //
    function transactThroughDerivativeMultilocation(
        uint8 transactor,
        uint16 index,
        Multilocation memory feeAsset,
        uint64 transactRequiredWeightAtMost,
        bytes memory innerCall,
        uint256 feeAmount,
        uint64 overallWeight
    ) external;

    // Transact through XCM using fee based on its currency_id
    // _custom:selector 185de2ae
    // _dev The token transfer burns/transfers the corresponding amount before sending
    // _param transactor The transactor to be used
    // _param index The index to be used
    // _param currencyId Address of the currencyId of the asset to be used for fees
    // It has to be a reserve of the destination chain
    // _param transactRequiredWeightAtMost The weight we want to buy in the destination chain
    // _param innerCall The inner call to be executed in the destination chain
    // _param feeAmount Amount to be used as fee.
    // _param overallWeight Overall weight to be used for the xcm message.
    function transactThroughDerivative(
        uint8 transactor,
        uint16 index,
        address currencyId,
        uint64 transactRequiredWeightAtMost,
        bytes memory innerCall,
        uint256 feeAmount,
        uint64 overallWeight
    ) external;

    // Transact through XCM using fee based on its multilocation through signed origins
    // _custom:selector d7ab340c
    // _dev No token is burnt before sending the message. The caller must ensure the destination
    // is able to undertand the DescendOrigin message, and create a unique account from which
    // dispatch the call
    // _param dest The destination chain (as multilocation) where to send the message
    // _param feeLocation The asset multilocation that indentifies the fee payment currency
    // It has to be a reserve of the destination chain
    // _param transactRequiredWeightAtMost The weight we want to buy in the destination chain for the call to be made
    // _param call The call to be executed in the destination chain
    // _param feeAmount Amount to be used as fee.
    // _param overallWeight Overall weight to be used for the xcm message.
    function transactThroughSignedMultilocation(
        Multilocation memory dest,
        Multilocation memory feeLocation,
        uint64 transactRequiredWeightAtMost,
        bytes memory call,
        uint256 feeAmount,
        uint64 overallWeight
    ) external;

    // Transact through XCM using fee based on its erc20 address through signed origins
    // _custom:selector b648f3fe
    // _dev No token is burnt before sending the message. The caller must ensure the destination
    // is able to undertand the DescendOrigin message, and create a unique account from which
    // dispatch the call
    // _param dest The destination chain (as multilocation) where to send the message
    // _param feeLocationAddress The ERC20 address of the token we want to use to pay for fees
    // only callable if such an asset has been BRIDGED to our chain
    // _param transactRequiredWeightAtMost The weight we want to buy in the destination chain for the call to be made
    // _param call The call to be executed in the destination chain
    // _param feeAmount Amount to be used as fee.
    // _param overallWeight Overall weight to be used for the xcm message.
    function transactThroughSigned(
        Multilocation memory dest,
        address feeLocationAddress,
        uint64 transactRequiredWeightAtMost,
        bytes memory call,
        uint256 feeAmount,
        uint64 overallWeight
    ) external;

    // _dev Encode 'utility.as_derivative' relay call
    // _custom:selector ff86378d
    // _param transactor The transactor to be used
    // _param index: The derivative index to use
    // _param innerCall: The inner call to be executed from the derivated address
    // _return result The bytes associated with the encoded call
    function encodeUtilityAsDerivative(uint8 transactor, uint16 index, bytes memory innerCall)
        external
        pure
        returns (bytes memory result);
}
