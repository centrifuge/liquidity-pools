// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.18;
pragma abicoder v2;

import {TypedMemView} from "memview-sol/TypedMemView.sol";
import {ConnectorMessages} from "../../Messages.sol";

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
    function handleTransfer(uint64 poolId, bytes16 trancheId, address destinationAddress, uint128 amount) external;
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

interface CentrifugeGatewayLike {
    function handle(bytes memory message) external;
}

contract ConnectorAxelarRouter is AxelarExecutableLike {
    using TypedMemView for bytes;
    // why bytes29? - https://github.com/summa-tx/memview-sol#why-bytes29
    using TypedMemView for bytes29;
    using ConnectorMessages for bytes29;

    mapping(address => uint256) public wards;

    ConnectorLike public immutable connector;
    AxelarGatewayLike public immutable axelarGateway;
    CentrifugeGatewayLike public centrifugeGateway;

    string public constant axelarCentrifugeChainId = "Centrifuge";
    string public constant axelarCentrifugeChainAddress = "";

    // --- Events ---
    event Rely(address indexed user);
    event Deny(address indexed user);
    event File(bytes32 indexed what, address addr);

    constructor(address connector_, address axelarGateway_) {
        connector = ConnectorLike(connector_);
        axelarGateway = AxelarGatewayLike(axelarGateway_);
        wards[msg.sender] = 1;
        emit Rely(msg.sender);
    }

    modifier auth() {
        require(wards[msg.sender] == 1, "ConnectorAxelarRouter/not-authorized");
        _;
    }

    modifier onlyCentrifugeChainOrigin(string memory sourceChain) {
        require(
            msg.sender == address(axelarGateway)
                && keccak256(bytes(axelarCentrifugeChainId)) == keccak256(bytes(sourceChain)),
            "ConnectorAxelarRouter/invalid-origin"
        );
        _;
    }

    modifier onlyConnector() {
        require(msg.sender == address(connector), "ConnectorAxelarRouter/only-connector-allowed-to-call");
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

    function file(bytes32 what, address gateway_) external auth {
        if (what == "gateway") {
            centrifugeGateway = CentrifugeGatewayLike(gateway_);
        } else {
            revert("ConnectorXCMRouter/file-unrecognized-param");
        }

        emit File(what, gateway_);
    }

    // --- Incoming ---
    function execute(bytes32, string calldata sourceChain, string calldata, bytes calldata payload)
        external
        onlyCentrifugeChainOrigin(sourceChain)
    {
        centrifugeGateway.handle(payload);
    }

    // --- Outgoing ---
    function send(bytes memory message) public onlyConnector {
        axelarGateway.callContract(axelarCentrifugeChainId, axelarCentrifugeChainAddress, message);
    }
}
