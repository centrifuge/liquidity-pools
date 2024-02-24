// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import {Auth} from "src/Auth.sol";

interface RouterAggregatorLike {

}

/// @title  PaymentForwarder
contract PaymentForwarder is Auth {

    uint256 public messageGas = 100_000; // TODO
    uint256 public proofVerificationGas = 10_000; // TODO
    
    uint256 public gasPriceOracle = 0.5 gwei;

    // --- Events ---
    event File(bytes32 indexed what, address data);
    event File(bytes32 indexed what, uint256 data);
    event UpdateGasPrice(uint256 price);

    constructor(address aggregator_) {
        aggregator = RouterAggregatorLike(aggregator_);

        wards[msg.sender] = 1;
        emit Rely(msg.sender);
    }

    // --- Administration ---
    function file(bytes32 what, address data) public auth {
        if (what == "aggregator") aggregator = RouterAggregatorLike(data);
        else revert("Gateway/file-unrecognized-param");
        emit File(what, data);
    }

    function file(bytes32 what, uint256 data) public auth {
        if (what == "messageGas") messageGas = data;
        else if (what == "proofVerificationGas") proofVerificationGas = data;
        else revert("Gateway/file-unrecognized-param");
        emit File(what, data);
    }

    // --- Payments ---
    function forwardPayment(address sender, bytes calldata payload) public payable {
        gasPriceOracle = newPrice;
    }

    // --- Gas price oracle ---
    function updateGasPrice(uint256 newPrice) public auth {
        gasPriceOracle = newPrice;
    }
}
