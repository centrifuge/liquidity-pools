// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.18;
pragma abicoder v2;

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

interface AxelarExecutableLike {
    function execute(
        bytes32 commandId,
        string calldata sourceChain,
        string calldata sourceAddress,
        bytes calldata payload
    ) external;
}

interface AxelarGatewayLike {
    function callContract(string calldata destinationChain, string calldata contractAddress, bytes calldata payload)
        external;
}

contract ConnectorAxelarXCMRouter is AxelarExecutableLike {
    address constant XCM_TRANSACTOR_V2_ADDRESS = 0x000000000000000000000000000000000000080D;

    mapping(address => uint256) public wards;
    //todo(nuno): do we really need this?
    mapping(bytes32 => uint32) public executedCalls;

    address public immutable centrifugeChainOrigin;
    /// The origin of EVM -> Centrifuge messages; the trusted source origin of the Axelar-bridged
    /// messages to be handled by this router.
    address public sourceOrigin;
    AxelarGatewayLike public immutable axelarGateway;
    XcmWeightInfo internal xcmWeightInfo;

    string public constant axelarCentrifugeChainId = "Centrifuge";
    string public constant axelarCentrifugeChainAddress = "";

    // --- Events ---
    event Rely(address indexed user);
    event Deny(address indexed user);
    event File(bytes32 indexed what, XcmWeightInfo xcmWeightInfo);
    event File(bytes32 indexed what, address addr);
    event Executed(bytes32 indexed payload);

    constructor(address centrifugeChainOrigin_, address axelarGateway_, address sourceOrigin_) {
        centrifugeChainOrigin = centrifugeChainOrigin_;
        axelarGateway = AxelarGatewayLike(axelarGateway_);
        sourceOrigin = sourceOrigin_;
        xcmWeightInfo = XcmWeightInfo({
            buyExecutionWeightLimit: 19000000000,
            transactWeightAtMost: 8000000000,
            feeAmount: 1000000000000000000
        });

        wards[msg.sender] = 1;
        emit Rely(msg.sender);
    }

    modifier auth() {
        require(wards[msg.sender] == 1, "ConnectorAxelarXCMRouter/not-authorized");
        _;
    }

    modifier onlyCentrifugeChainOrigin() {
        require(msg.sender == address(centrifugeChainOrigin), "ConnectorAxelarXCMRouter/invalid-origin");
        _;
    }

    modifier onlySourceOrigin() {
        require(msg.sender == address(sourceOrigin), "ConnectorAxelarXCMRouter/only-source-origin-allowed-to-call");
        _;
    }

    // --- Administration ---
    function rely(address user) external auth {
        wards[user] = 1;
        emit Rely(user);
    }

    function deny(address user) external auth {
        wards[user] = 0;
        emit Deny(user);
    }

    function file(bytes32 what, address sourceOrigin_) external auth {
        if (what == "sourceOrigin") {
            sourceOrigin = sourceOrigin_;
            emit File(what, sourceOrigin_);
        } else {
            revert("ConnectorXCMRouter/file-unrecognized-param");
        }
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
    // A message that's coming from another EVM chain, headed to the Centrifuge Chain.
    function execute(bytes32, string calldata sourceChain, string calldata, bytes calldata payload)
        external
        onlySourceOrigin
    {
        // todo(nuno): why do we hash this?
        bytes32 hh = keccak256(payload);

        XcmTransactorV2 transactorContract = XcmTransactorV2(XCM_TRANSACTOR_V2_ADDRESS);

        transactorContract.transactThroughSignedMultilocation(
            // dest chain
            centrifuge_parachain_multilocation(),
            // fee asset
            cfg_asset_multilocation(),
            // the weight limit for the transact call execution
            xcmWeightInfo.transactWeightAtMost,
            // the call to be executed on the cent chain
            payload,
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
        payable
        onlyCentrifugeChainOrigin
    {
        axelarGateway.callContract(destinationChain, destinationAddress, payload);
    }

    function centrifuge_parachain_multilocation() internal pure returns (Multilocation memory) {
        bytes[] memory interior = new bytes[](1);
        interior[0] = parachain_id();

        return Multilocation({parents: 1, interior: interior});
    }

    function cfg_asset_multilocation() internal pure returns (Multilocation memory) {
        bytes[] memory interior = new bytes[](2);
        interior[0] = parachain_id();
        // Multilocation V3
        // GeneralKey prefix - 06
        // Length - 2 bytes
        // 0001 + padded to 32 bytes
        interior[1] = hex"06020001000000000000000000000000000000000000000000000000000000000000";

        return Multilocation({parents: 1, interior: interior});
    }

    function parachain_id() internal pure returns (bytes memory) {
        return abi.encodePacked(uint8(0), uint32(2031));
    }
}
