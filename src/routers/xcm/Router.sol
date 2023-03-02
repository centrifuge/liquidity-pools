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

    /// --- Properties ---
    ConnectorLike public immutable connector;
    address immutable centrifugeChainOrigin;
    bytes centrifugeChainHandleCallIndex;
    XcmWeightInfo xcmWeightInfo;

    /// --- Storage ---
    /// Auth storage
    mapping(address => uint256) public wards;

    /// --- Events ---
    event Rely(address indexed user);
    event Deny(address indexed user);
    event File(bytes32 indexed what, XcmWeightInfo xcmWeightInfo);

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
        wards[msg.sender] = 1;
    }

    /// -- Auth ---
    modifier auth() {
        require(wards[msg.sender] == 1, "ConnectorXCMRouter/not-authorized");
        _;
    }

    function rely(address usr) external auth {
        wards[usr] = 1;
        emit Rely(usr);
    }

    function deny(address usr) external auth {
        wards[usr] = 0;
        emit Deny(usr);
    }

    modifier onlyCentrifugeChainOrigin() {
        require(msg.sender == address(centrifugeChainOrigin), "ConnectorXCMRouter/invalid-origin");
        _;
    }

    modifier onlyConnector() {
        require(msg.sender == address(connector), "ConnectorXCMRouter/only-connector-allowed-to-call");
        _;
    }

    function file(bytes32 what, uint64 buyExecutionWeightLimit, uint64 transactWeightAtMost, uint256 feeAmount)
        external
        auth
    {
        if (what == "xcmWeightInfo") {
            xcmWeightInfo = XcmWeightInfo(buyExecutionWeightLimit, transactWeightAtMost, feeAmount);
        } else {
            revert("CentrifugeConnector/file-unrecognized-param");
        }

        emit File(what, xcmWeightInfo);
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

    function send(bytes memory message) public onlyConnector {
        bytes memory centChainCall = centrifuge_handle_call(message);

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

    function centrifuge_handle_call(bytes memory message) internal view returns (bytes memory) {
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

    // Docs on the encoding of a MultiLocation value can be found here:
    // https://docs.moonbeam.network/builders/interoperability/xcm/xcm-transactor/
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

    function parachain_id() internal pure returns (bytes memory) {
        return abi.encodePacked(uint8(0), uint32(2031));
    }
}
