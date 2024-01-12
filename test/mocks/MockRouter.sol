// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import "forge-std/Test.sol";
import {Auth} from "src/Auth.sol";
import "./Mock.sol";

interface AggregatorLike {
    function handle(bytes memory message) external;
}

contract MockRouter is Auth, Mock {
    AggregatorLike public immutable aggregator;

    mapping(bytes => uint256) public sent;

    constructor(address aggregator_) {
        aggregator = AggregatorLike(aggregator_);

        wards[msg.sender] = 1;
    }

    function execute(bytes memory _message) external {
        AggregatorLike(aggregator).handle(_message);
    }

    function send(bytes memory message) public {
        values_bytes["send"] = message;
        sent[message]++;
    }

    // Added to be ignored in coverage report
    function test() public {}
}
