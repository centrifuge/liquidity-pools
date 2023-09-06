// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import {Messages} from "../../Messages.sol";
import {Auth} from "./../../../util/Auth.sol";

struct Multilocation {
    uint8 parents;
    bytes[] interior;
}

// https://github.com/PureStake/moonbeam/blob/v0.30.0/precompiles/xcm-transactor/src/v2/XcmTransactorV2.sol#L12
interface XcmTransactorV2 {
    function transactThroughSignedMultilocation(
        Multilocation memory dest,
        Multilocation memory feeLocation,
        uint64 transactRequiredWeightAtMost,
        bytes memory call,
        uint256 feeAmount,
        uint64 overallWeight
    ) external;
}

struct XcmWeightInfo {
    // The weight limit in Weight units we accept amount to pay for the
    // execution of the whole XCM on the Centrifuge. This should be
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

interface GatewayLike {
    function handle(bytes memory message) external;
}

/// @title  XCM Router
/// @notice Routing contract that integrates with the XCM transact precompile.
contract XCMRouter is Auth {
    address constant XCM_TRANSACTOR_V2_ADDRESS = 0x000000000000000000000000000000000000080D;
    uint32 private constant CENTRIFUGE_PARACHAIN_ID = 2031;

    XcmWeightInfo internal xcmWeightInfo;

    GatewayLike public gateway;
    address public immutable centrifugeChainOrigin;
    uint8 public immutable centrifugeChainLiquidityPoolsPalletIndex;
    uint8 public immutable centrifugeChainLiquidityPoolsPalletHandleIndex;

    // --- Events ---
    event File(bytes32 indexed what, XcmWeightInfo xcmWeightInfo);
    event File(bytes32 indexed what, address addr);

    constructor(
        address centrifugeChainOrigin_,
        uint8 centrifugeChainLiquidityPoolsPalletIndex_,
        uint8 centrifugeChainLiquidityPoolsPalletHandleIndex_
    ) {
        centrifugeChainOrigin = centrifugeChainOrigin_;
        centrifugeChainLiquidityPoolsPalletIndex = centrifugeChainLiquidityPoolsPalletIndex_;
        centrifugeChainLiquidityPoolsPalletHandleIndex = centrifugeChainLiquidityPoolsPalletHandleIndex_;
        xcmWeightInfo = XcmWeightInfo({
            buyExecutionWeightLimit: 19000000000,
            transactWeightAtMost: 8000000000,
            feeAmount: 1000000000000000000
        });

        wards[msg.sender] = 1;
        emit Rely(msg.sender);
    }

    modifier onlyCentrifugeChainOrigin() {
        require(msg.sender == address(centrifugeChainOrigin), "XCMRouter/invalid-origin");
        _;
    }

    modifier onlyGateway() {
        require(msg.sender == address(gateway), "XCMRouter/only-gateway-allowed-to-call");
        _;
    }

    // --- Administration ---
    function file(bytes32 what, address gateway_) external auth {
        if (what == "gateway") {
            gateway = GatewayLike(gateway_);
        } else {
            revert("XCMRouter/file-unrecognized-param");
        }

        emit File(what, gateway_);
    }

    function file(bytes32 what, uint64 buyExecutionWeightLimit, uint64 transactWeightAtMost, uint256 feeAmount)
        external
        auth
    {
        if (what == "xcmWeightInfo") {
            xcmWeightInfo = XcmWeightInfo(buyExecutionWeightLimit, transactWeightAtMost, feeAmount);
        } else {
            revert("CentrifugeXCMRouter/file-unrecognized-param");
        }

        emit File(what, xcmWeightInfo);
    }

    // --- Incoming ---
    function handle(bytes memory _message) external onlyCentrifugeChainOrigin {
        gateway.handle(_message);
    }

    // --- Outgoing ---
    function send(bytes memory message) public onlyGateway {
        bytes memory centChainCall = _centrifugeHandleCall(message);

        XcmTransactorV2 transactorContract = XcmTransactorV2(XCM_TRANSACTOR_V2_ADDRESS);

        transactorContract.transactThroughSignedMultilocation(
            // dest chain
            _centrifugeParachainMultilocation(),
            // fee asset
            _cfgAssetMultilocation(),
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

    // --- Utilities ---
    function _centrifugeHandleCall(bytes memory message) internal view returns (bytes memory) {
        return abi.encodePacked(
            // The Centrifuge liquidity-pools pallet index
            centrifugeChainLiquidityPoolsPalletIndex,
            // The `handle` call index within the liquidity-pools pallet
            centrifugeChainLiquidityPoolsPalletHandleIndex,
            // We need to specify the length of the message in the scale-encoding format
            messageLengthScaleEncoded(message),
            // The connector message itself
            message
        );
    }

    // Obtain the Scale-encoded length of a given message. Each Liquidity Pools Message is fixed-sized and
    // have thus a fixed scale-encoded length associated to which message variant (aka Call).
    function messageLengthScaleEncoded(bytes memory _msg) internal pure returns (bytes memory) {
        if (Messages.isTransfer(_msg)) {
            return hex"8501";
        } else if (Messages.isTransferTrancheTokens(_msg)) {
            // A TransferTrancheTokens message is 82 bytes long which encodes to 0x4901 in Scale
            return hex"4901";
        } else if (Messages.isIncreaseInvestOrder(_msg)) {
            return hex"6501";
        } else if (Messages.isDecreaseInvestOrder(_msg)) {
            return hex"6501";
        } else if (Messages.isIncreaseRedeemOrder(_msg)) {
            return hex"6501";
        } else if (Messages.isDecreaseRedeemOrder(_msg)) {
            return hex"6501";
        } else if (Messages.isCollectInvest(_msg)) {
            return hex"e4";
        } else if (Messages.isCollectRedeem(_msg)) {
            return hex"e4";
        } else {
            revert("XCMRouter/unsupported-outgoing-message");
        }
    }

    // Docs on the encoding of a MultiLocation value can be found here:
    // https://docs.moonbeam.network/builders/interoperability/xcm/xcm-transactor/
    function _centrifugeParachainMultilocation() internal pure returns (Multilocation memory) {
        bytes[] memory interior = new bytes[](1);
        interior[0] = _parachainId();

        return Multilocation({parents: 1, interior: interior});
    }

    function _cfgAssetMultilocation() internal pure returns (Multilocation memory) {
        bytes[] memory interior = new bytes[](2);
        interior[0] = _parachainId();
        interior[1] = hex"060001";

        return Multilocation({parents: 1, interior: interior});
    }

    function _parachainId() internal pure returns (bytes memory) {
        return abi.encodePacked(uint8(0), CENTRIFUGE_PARACHAIN_ID);
    }
}
