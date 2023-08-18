// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.18;
pragma abicoder v2;

import {TypedMemView} from "memview-sol/TypedMemView.sol";
import "forge-std/Test.sol";
import {InvestmentManager} from "src/InvestmentManager.sol";
import {Messages} from "src/Messages.sol";
import {Gateway} from "src/Gateway.sol";

contract MockXcmRouter is Test {
    using TypedMemView for bytes;
    using TypedMemView for bytes29;

    address public immutable centrifugeChainOrigin;
    address public gateway;

    mapping(address => uint256) public wards;
    mapping(bytes => bool) public sentMessages;

    constructor(address centrifugeChainOrigin_) {
        centrifugeChainOrigin = centrifugeChainOrigin_;
        wards[msg.sender] = 1;
    }

    modifier auth() {
        require(wards[msg.sender] == 1, "ConnectorRouter/not-authorized");
        _;
    }

    function rely(address user) external auth {
        wards[user] = 1;
    }

    function deny(address user) external auth {
        wards[user] = 0;
    }

    modifier onlyCentrifugeChainOrigin() {
        require(msg.sender == address(centrifugeChainOrigin), "ConnectorXCMRouter/invalid-origin");
        _;
    }

    modifier onlyGateway() {
        require(msg.sender == address(gateway), "ConnectorXCMRouter/only-gateway-allowed-to-call");
        _;
    }

    function file(bytes32 what, address addr) external {
        if (what == "gateway") {
            gateway = addr;
        } else {
            revert("ConnectorXCMRouter/file-unrecognized-param");
        }
    }

    function handle(bytes memory _message) external {
        Gateway(gateway).handle(_message);
    }

    function send(bytes memory message) public onlyGateway {
        sentMessages[message] = true;
    }
}
