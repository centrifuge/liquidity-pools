// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import "forge-std/Test.sol";
import {InvestmentManager} from "src/InvestmentManager.sol";
import {Gateway} from "src/gateway/Gateway.sol";
import {Auth} from "src/Auth.sol";
import "./Mock.sol";

contract MockRouter is Auth, Mock {
    address public immutable centrifugeChainOrigin;
    address public gateway;

    mapping(bytes => bool) public sentMessages;

    constructor(address centrifugeChainOrigin_) {
        centrifugeChainOrigin = centrifugeChainOrigin_;
        wards[msg.sender] = 1;
    }

    modifier onlyCentrifugeChainOrigin() {
        require(msg.sender == address(centrifugeChainOrigin), "MockRouter/invalid-origin");
        _;
    }

    modifier onlyGateway() {
        require(msg.sender == address(gateway), "MockRouter/only-gateway-allowed-to-call");
        _;
    }

    function file(bytes32 what, address addr) external {
        if (what == "gateway") {
            gateway = addr;
        } else {
            revert("MockRouter/file-unrecognized-param");
        }
    }

    function execute(bytes memory _message) external {
        Gateway(gateway).handle(_message);
    }

    function send(bytes memory message) public onlyGateway {
        values_bytes["send"] = message;
        sentMessages[message] = true;
    }

    // Added to be ignored in coverage report
    function test() public {}
}
