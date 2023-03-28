// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.18;
pragma abicoder v2;

import {TypedMemView} from "memview-sol/TypedMemView.sol";
import {ConnectorMessages} from "../../Messages.sol";

interface CentrifugeGatewayLike {
    function handle(bytes memory message) external;
}

interface ChainBridgeLike {
    function deposit(uint8 destinationChainID, bytes32 resourceID, bytes calldata data) external payable;
}

interface ChainBridgeDepositExecuteLike {
    function executeProposal(bytes32 resourceID, bytes calldata data) external;
}

contract ConnectorChainBridgeRouter is ChainBridgeDepositExecuteLike {
    using TypedMemView for bytes;
    // why bytes29? - https://github.com/summa-tx/memview-sol#why-bytes29
    using TypedMemView for bytes29;
    using ConnectorMessages for bytes29;

    mapping(address => uint256) public wards;

    CentrifugeGatewayLike public gateway;
    ChainBridgeLike public immutable bridge;

    // TODO: figure out all these parameters
    uint256 public constant deposit = 0.01 ether;
    uint8 public constant centrifugeChainId = 1;
    bytes32 public constant resourceID = "1";

    constructor(address bridge_) {
        bridge = ChainBridgeLike(bridge_);
    }

    modifier auth() {
        require(wards[msg.sender] == 1, "ConnectorXCMRouter/not-authorized");
        _;
    }

    modifier onlyChainBridgeOrigin() {
        require(msg.sender == address(bridge), "ConnectorChainBridgeRouter/invalid-origin");
        _;
    }

    modifier onlyGateway() {
        require(msg.sender == address(gateway), "ConnectorChainBridgeRouter/only-gateway-allowed-to-call");
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
            gateway = GatewayLike(gateway_);
        } else {
            revert("ConnectorChainBridgeRouter/file-unrecognized-param");
        }

        emit File(what, gateway_);
    }

    // --- Incoming ---
    function executeProposal(bytes32, bytes calldata payload) external onlyChainBridgeOrigin {
        gateway.handle(payload);
    }

    // --- Outgoing ---
    function send(bytes memory message) public onlyGateway {
        bridge.deposit(centrifugeChainId, resourceID, message);
    }
}
