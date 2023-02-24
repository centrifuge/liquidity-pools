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

    constructor(address connector_, address centrifugeChainOrigin_, bytes memory centrifugeChainHandleCallIndex_) {
        connector = ConnectorLike(connector_);
        centrifugeChainOrigin = centrifugeChainOrigin_;
        centrifugeChainHandleCallIndex = centrifugeChainHandleCallIndex_;
    }

    modifier onlyCentrifugeChainOrigin() {
        require(msg.sender == address(centrifugeChainOrigin), "ConnectorXCMRouter/invalid-origin");
        _;
    }

    modifier onlyConnector() {
        require(msg.sender == address(connector), "ConnectorXCMRouter/only-connector-allowed-to-call");
        _;
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

    // todo(nuno): add `onlyConnector` modifier back once tested calling this directly
    function sendMessage(uint64 poolId, bytes16 trancheId, uint128 amount, address destinationAddress) external {
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
            5_000_000_000,
            // the call to be executed on the cent chain
            centChainCall,
            // feeAmount
            500_000_000_000_000,
            // overall XCM weight, the total weight the XCM-transactor extrinsic can use.
            // This includes all the XCM instructions plus the weight of the call itself.
            10_000_000_000
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

    function centrifuge_handle_call(bytes memory message) internal view returns (bytes memory) {
        return abi.encodePacked(
            // The call index; first byte is the pallet, the second is the extrinsic
            centrifugeChainHandleCallIndex,
            // We need to specify the length of the message in the scale-encoding format
            // A transfer message has 82 bytes which encodes to 4901 in Scale :shrug:
            // TODO(nuno): The length is fixed on a per message call type basis; we will need to support other types
            hex"4901",
            // the connector message itself
            message
        );
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
