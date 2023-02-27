// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.7.6;
pragma abicoder v2;

import {TypedMemView} from "memview-sol/TypedMemView.sol";
import {ConnectorMessages} from "../../Messages.sol";
import {XCM_TRANSACTOR_V2_CONTRACT, Multilocation} from "../../../lib/moonbeam-xcm-transactor/XcmTransactorV2.sol";

interface ConnectorLike {
    function addPool(uint64 poolId) external;
    function addTranche(
        uint64 poolId,
        bytes16 trancheId,
        string memory tokenName,
        string memory tokenSymbol,
        uint128 price
    ) external;
    function updateMember(uint64 poolId, bytes16 trancheId, address user, uint64 validUntil) external;
    function updateTokenPrice(uint64 poolId, bytes16 trancheId, uint128 price) external;
    function handleTransfer(uint64 poolId, bytes16 trancheId, address user, uint128 amount) external;
}

contract ConnectorXCMRouter {
    using TypedMemView for bytes;
    // why bytes29? - https://github.com/summa-tx/memview-sol#why-bytes29
    using TypedMemView for bytes29;
    using ConnectorMessages for bytes29;

    /// Properties
    ConnectorLike public immutable connector;
    address centrifugeChainOrigin;
    bytes centrifugeChainHandleCallIndex;
    XcmWeightInfo xcmWeightInfo;

    // Types
    struct XcmWeightInfo {
        // The weight limit in Weight units we accept amount to pay for the
        // execution of the whole XCM on the Centrifuge chain. This should be
        // transactWeightAtMost + an extra amount to cover for the other
        // instructions in the XCM message.
        uint64 buyExecutionWeightLimit;
        // The weight limit in Weight units we accept paying for having the Transact
        // call be executed. This is the cost associated with executing the handle call
        // in the Centrifuge.
        uint64 transactWeightAtMost;
        // The amount to cover for the fees. It will be used in XCM to buy
        // execution and thus have credit for pay those fees.
        uint256 feeAmount;
    }

    constructor(address connector_, address centrifugeChainOrigin_, bytes memory centrifugeChainHandleCallIndex_) {
        connector = ConnectorLike(connector_);
        centrifugeChainOrigin = centrifugeChainOrigin_;
        centrifugeChainHandleCallIndex = centrifugeChainHandleCallIndex_;
        xcmWeightInfo = XcmWeightInfo({
            buyExecutionWeightLimit: 19000000000,
            transactWeightAtMost: 8000000000,
            feeAmount: 1000000000000000000
        });
    }

    modifier onlyCentrifugeChainOrigin() {
        require(msg.sender == address(centrifugeChainOrigin), "ConnectorXCMRouter/invalid-origin");
        _;
    }

    modifier onlyConnector() {
        require(msg.sender == address(connector), "ConnectorXCMRouter/only-connector-allowed-to-call");
        _;
    }

    // todo(nuno): add auth modifier
    function updateXcmWeights(uint64 buyExecutionWeightLimit, uint64 transactWeightAtMost, uint256 feeAmount)
        external
    {
        xcmWeightInfo = XcmWeightInfo(buyExecutionWeightLimit, transactWeightAtMost, feeAmount);
    }

    function handle(bytes memory _message) external onlyCentrifugeChainOrigin {
        bytes29 _msg = _message.ref(0);
        if (ConnectorMessages.isAddPool(_msg)) {
            uint64 poolId = ConnectorMessages.parseAddPool(_msg);
            connector.addPool(poolId);
        } else if (ConnectorMessages.isAddTranche(_msg)) {
            (uint64 poolId, bytes16 trancheId, string memory tokenName, string memory tokenSymbol, uint128 price) =
                ConnectorMessages.parseAddTranche(_msg);
            connector.addTranche(poolId, trancheId, tokenName, tokenSymbol, price);
        } else if (ConnectorMessages.isUpdateMember(_msg)) {
            (uint64 poolId, bytes16 trancheId, address user, uint64 validUntil) =
                ConnectorMessages.parseUpdateMember(_msg);
            connector.updateMember(poolId, trancheId, user, validUntil);
        } else if (ConnectorMessages.isUpdateTokenPrice(_msg)) {
            (uint64 poolId, bytes16 trancheId, uint128 price) = ConnectorMessages.parseUpdateTokenPrice(_msg);
            connector.updateTokenPrice(poolId, trancheId, price);
        } else if (ConnectorMessages.isTransfer(_msg)) {
            (uint64 poolId, bytes16 trancheId,, address user, uint128 amount) = ConnectorMessages.parseTransfer(_msg);
            connector.handleTransfer(poolId, trancheId, user, amount);
        } else {
            require(false, "invalid-message");
        }
    }

    function send(bytes memory message) external onlyConnector {
        bytes memory centChainCall = centrifuge_handle_call(message);
        XcmWeightInfo memory xcmWeightInfo =
            XcmWeightInfo({buyExecutionWeightLimit: 1, transactWeightAtMost: 2, feeAmount: 3});

        XCM_TRANSACTOR_V2_CONTRACT.transactThroughSignedMultilocation(
            // dest chain
            centrifuge_parachain_multilocation(),
            // fee asset
            cfg_asset_multilocation(),
            // the weight limit for the transact call execution
            xcmWeightInfo.transactWeightAtMost,
            // the call to be executed on the cent chain
            centChainCall,
            // the CFG we offer to pay for execution fees of the whole XCM
            xcmWeightInfo.feeAmount,
            // overall XCM weight, the total weight the XCM-transactor extrinsic can use.
            // This includes all the XCM instructions plus the weight of the Transact call itself.
            xcmWeightInfo.buyExecutionWeightLimit
        );
    }

    // todo(nuno): add `onlyConnector` modifier back once tested calling this directly
    function sendMessageDebug(
        uint64 poolId,
        bytes16 trancheId,
        uint128 amount,
        address destinationAddress,
        uint256 feeAmount,
        uint64 buyExecutionWeightLimit,
        uint64 transactWeightAtMost
    ) external {
        bytes memory centChainCall = centrifuge_handle_call(
            ConnectorMessages.formatTransfer(
                poolId,
                trancheId,
                ConnectorMessages.formatDomain(ConnectorMessages.Domain.Centrifuge),
                destinationAddress,
                amount
            )
        );

        XCM_TRANSACTOR_V2_CONTRACT.transactThroughSignedMultilocation(
            // dest chain
            centrifuge_parachain_multilocation(),
            // fee asset
            cfg_asset_multilocation(),
            // requireWeightAtMost
            transactWeightAtMost,
            // the call to be executed on the cent chain
            centChainCall,
            // feeAmount
            feeAmount,
            // overall XCM weight, the total weight the XCM-transactor extrinsic can use.
            // This includes all the XCM instructions plus the weight of the call itself.
            buyExecutionWeightLimit
        );
    }

    // todo(nuno): make call internal once debugging is complete
    function centrifuge_handle_call(bytes memory message) external view returns (bytes memory) {
        return abi.encodePacked(
            // The call index; first byte is the pallet, the second is the extrinsic
            centrifugeChainHandleCallIndex,
            // We need to specify the length of the message in the scale-encoding format
            message_length_scale_encoded(message),
            // The connector message itself
            message
        );
    }

    // Obtain the Scale-encoded length of a given message. Each Connector Message is fixed-sized and
    // have thus a fixed scale-encoded length associated to which message variant (aka Call).
    function message_length_scale_encoded(bytes memory message) internal pure returns (bytes memory) {
        bytes29 _msg = message.ref(0);

        if (ConnectorMessages.isTransfer(_msg)) {
            // A transfer message is 82 bytes long which encodes to 0x4901 in Scale
            return hex"4901";
        } else {
            revert("ConnectorXCMRouter/unsupported-outgoing-message");
        }
    }

    function centrifuge_parachain_multilocation() internal pure returns (Multilocation memory) {
        bytes[] memory interior = new bytes[](1);
        interior[0] = parachain_id();

        return Multilocation({parents: 1, interior: interior});
    }

    function cfg_asset_multilocation() internal pure returns (Multilocation memory) {
        bytes[] memory interior = new bytes[](2);
        interior[0] = parachain_id();
        interior[1] = hex"060001";

        return Multilocation({parents: 1, interior: interior});
    }

    /*
       Docs: https://docs.moonbeam.network/builders/interoperability/xcm/xcm-transactor/
       XCM Multilocation interior

           0x00	Parachain	bytes4
           0x01	AccountId32	bytes32
           0x02	AccountIndex64	u64
           0x03	AccountKey20	bytes20
           0x04	PalletInstance	byte
           0x05	GeneralIndex	u128
           0x06	GeneralKey	bytes[]


       Examples

       Parachain	"0x00+000007E7"	Parachain ID 2023
       AccountId32	"0x01+AccountId32+00"	AccountId32, Network Any
       AccountKey20	"0x03+AccountKey20+00"	AccountKey20, Network Any
       PalletInstance	"0x04+03"	Pallet Instance 3

    */

    function parachain_id() internal pure returns (bytes memory) {
        return abi.encodePacked(uint8(0), uint32(2031));
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
