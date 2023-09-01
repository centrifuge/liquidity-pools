// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.18;
pragma abicoder v2;

import {AxelarExecutable} from "./AxelarExecutable.sol";
import "./../../../util/Auth.sol";

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

contract AxelarXCMRelayer is Auth, AxelarExecutable {
    address constant XCM_TRANSACTOR_V2_ADDRESS = 0x000000000000000000000000000000000000080D;

    address public immutable centrifugeChainOrigin;
    mapping(string => string) public axelarEVMRouters;
    bytes1 public immutable lpPalletIndex;
    bytes1 public immutable lpCallIndex;

    XcmWeightInfo public xcmWeightInfo;

    //todo(nuno): do we really need this?
    mapping(bytes32 => uint32) public executedCalls;

    // --- Events ---
    event File(bytes32 indexed what, XcmWeightInfo xcmWeightInfo);
    event File(bytes32 indexed what, string chain, string addr);
    event Executed(bytes32 indexed payload);

    constructor(address centrifugeChainOrigin_, address axelarGateway_, bytes1 lpPalletIndex_, bytes1 lpCallIndex_)
        AxelarExecutable(axelarGateway_)
    {
        centrifugeChainOrigin = centrifugeChainOrigin_;
        lpPalletIndex = lpPalletIndex_;
        lpCallIndex = lpCallIndex_;

        xcmWeightInfo = XcmWeightInfo({
            buyExecutionWeightLimit: 19000000000,
            transactWeightAtMost: 8000000000,
            feeAmount: 1000000000000000000
        });

        wards[msg.sender] = 1;
        emit Rely(msg.sender);
    }

    modifier onlyCentrifugeChain() {
        require(msg.sender == address(centrifugeChainOrigin), "AxelarXCMRelayer/only-centrifuge-chain-allowed");
        _;
    }

    modifier onlyAxelarEVMRouter(string memory sourceChain, string memory sourceAddress) {
        require(
            keccak256(abi.encodePacked(axelarEVMRouters[sourceChain])) == keccak256(abi.encodePacked(sourceAddress)),
            "AxelarXCMRelayer/only-axelar-evm-router-allowed"
        );
        _;
    }

    // --- Administration ---
    function file(bytes32 what, string memory axelarEVMRouterChain, string memory axelarEVMRouterAddress)
        external
        auth
    {
        if (what == "axelarEVMRouter") {
            axelarEVMRouters[axelarEVMRouterChain] = axelarEVMRouterAddress;
        } else {
            revert("AxelarXCMRelayer/file-unrecognized-param");
        }

        emit File(what, axelarEVMRouterChain, axelarEVMRouterAddress);
    }

    function file(bytes32 what, uint64 buyExecutionWeightLimit, uint64 transactWeightAtMost, uint256 feeAmount)
        external
        auth
    {
        if (what == "xcmWeightInfo") {
            xcmWeightInfo = XcmWeightInfo(buyExecutionWeightLimit, transactWeightAtMost, feeAmount);
        } else {
            revert("AxelarXCMRelayer/file-unrecognized-param");
        }

        emit File(what, xcmWeightInfo);
    }

    // --- Incoming ---
    // A message that's coming from another EVM chain, headed to the Centrifuge Chain.
    function _execute(bytes32, string calldata sourceChain, string calldata sourceAddress, bytes calldata payload)
        public
        onlyAxelarEVMRouter(sourceChain, sourceAddress)
    {
        // todo(nuno): why do we hash this?
        bytes32 hh = keccak256(payload);

        XcmTransactorV2 transactorContract = XcmTransactorV2(XCM_TRANSACTOR_V2_ADDRESS);

        bytes memory payloadWithLocation = bytes.concat(
            lpPalletIndex,
            lpCallIndex,
            bytes32(bytes(sourceChain).length),
            bytes(sourceChain),
            bytes32(bytes(sourceAddress).length),
            bytes(sourceAddress),
            payload
        );

        transactorContract.transactThroughSignedMultilocation(
            // dest chain
            _centrifugeParachainMultilocation(),
            // fee asset
            _cfgAssetMultilocation(),
            // the weight limit for the transact call execution
            xcmWeightInfo.transactWeightAtMost,
            // the call to be executed on the cent chain
            payloadWithLocation,
            // the CFG we offer to pay for execution fees of the whole XCM
            xcmWeightInfo.feeAmount,
            // overall XCM weight, the total weight the XCM-transactor extrinsic can use.
            // This includes all the XCM instructions plus the weight of the Transact call itself.
            xcmWeightInfo.buyExecutionWeightLimit
        );

        executedCalls[hh] = 1;
        emit Executed(hh);

        return;
    }

    // --- Outgoing ---
    // A message that has been sent from the Centrifuge Chain, heading to a specific destination EVM chain
    function send(string calldata destinationChain, string calldata destinationAddress, bytes calldata payload)
        external
        onlyCentrifugeChain
    {
        axelarGateway.callContract(destinationChain, destinationAddress, payload);
    }

    function _centrifugeParachainMultilocation() internal pure returns (Multilocation memory) {
        bytes[] memory interior = new bytes[](1);
        interior[0] = _parachainId();

        return Multilocation({parents: 1, interior: interior});
    }

    function _cfgAssetMultilocation() internal pure returns (Multilocation memory) {
        bytes[] memory interior = new bytes[](2);
        interior[0] = _parachainId();
        // Multilocation V3
        // GeneralKey prefix - 06
        // Length - 2 bytes
        // 0001 + padded to 32 bytes
        interior[1] = hex"06020001000000000000000000000000000000000000000000000000000000000000";

        return Multilocation({parents: 1, interior: interior});
    }

    function _parachainId() internal pure returns (bytes memory) {
        return abi.encodePacked(uint8(0), uint32(2031));
    }
}
