// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.7.6;
pragma abicoder v2;

address constant XCM_TRANSACTOR_V1_ADDRESS = 0x0000000000000000000000000000000000000806;

XcmTransactorV1 constant XCM_TRANSACTOR_V1_CONTRACT = XcmTransactorV1(
    XCM_TRANSACTOR_V1_ADDRESS
);

// A multilocation is defined by its number of parents and the encoded junctions (interior)
struct Multilocation {
    uint8 parents;
    bytes[] interior;
}

interface XcmTransactorV1 {


    function indexToAccount(uint16 index) external view returns (address owner);

    function transactInfo(Multilocation memory multilocation)
        external
        view
        returns (
            uint64 transactExtraWeight,
            uint256 feePerSecond,
            uint64 maxWeight
        );


    function transactInfoWithSigned(Multilocation memory multilocation)
        external
        view
        returns (
            uint64 transactExtraWeight,
            uint64 transactExtraWeightSigned,
            uint64 maxWeight
        );

    function feePerSecond(Multilocation memory multilocation)
        external
        view
        returns (uint256 feePerSecond);

    function transactThroughDerivativeMultilocation(
        uint8 transactor,
        uint16 index,
        Multilocation memory feeAsset,
        uint64 weight,
        bytes memory innerCall
    ) external;

    function transactThroughDerivative(
        uint8 transactor,
        uint16 index,
        address currencyId,
        uint64 weight,
        bytes memory innerCall
    ) external;

    function transactThroughSignedMultilocation(
        Multilocation memory dest,
        Multilocation memory feeLocation,
        uint64 weight,
        bytes memory call
    ) external;

    function transactThroughSigned(
        Multilocation memory dest,
        address feeLocationAddress,
        uint64 weight,
        bytes memory call
    ) external;

    function encodeUtilityAsDerivative(uint8 transactor, uint16 index, bytes memory innerCall)
        external
        pure
        returns (bytes memory result);
}