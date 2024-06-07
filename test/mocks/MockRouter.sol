// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import "forge-std/Test.sol";
import {Auth} from "src/Auth.sol";
import "test/mocks/Mock.sol";

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

    function send(bytes calldata message) public {
        values_bytes["send"] = message;
        sent[message]++;
    }

    function estimate(bytes calldata, uint256) public view returns (uint256 estimation) {
        estimation = values_uint256_return["estimate"];
    }

    function pay(bytes calldata, address) external payable {
        callWithValue("pay", msg.value);
    }
    // Added to be ignored in coverage report

    function test() public {}
}
