// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import {Auth} from "src/Auth.sol";
import {IAggregatorV3} from "src/interfaces/IAggregatorV3.sol";

contract GasService is IAggregatorV3, Auth {
    uint8 public constant decimals = 18;
    string public constant description = "CFG/ETH price feed";
    uint256 public constant version = 1;

    uint80 roundId;
    uint256 updatedTime;
    uint256 price;
    uint256 cost;

    event File(bytes32 what, uint256 value);

    constructor(uint256 cost_, uint256 price_) {
        cost = cost_;
        price = price_;
        updatedTime = block.timestamp;
        roundId = 1;
    }

    function file(bytes32 what, uint256 value) external auth {
        if (what == "cost") {
            cost = value;
        }
        if (what == "price") {
            price = value;
            roundId++;
            updatedTime = block.timestamp;
        } else {
            revert("CentrifugeGasService/file-unrecognized-param");
        }
        emit File(what, value);
    }

    function estimate(bytes calldata) public view returns (uint256) {
        // TODO Actual calculation based on the  price anbd cost
        // This is basically the `wmul` from ds-math. Do we want to integrate their math lib?
        // Or do we want to extend our math lib?
        return ((cost * price) + (10 ** 18 / 2)) / 10 ** 18;
    }

    function getRoundData(uint80) public view returns (uint80, int256, uint256, uint256) {
        // TODO Not sure if we need this check at all. Further investigate how casting works ..
        require(price < uint256(type(int256).max), "cannot-cast");
        return (roundId, int256(price), updatedTime, updatedTime);
    }

    function latestRoundData() public view returns (uint80, int256, uint256, uint256) {
        // Current version doesn't suport different rounds id lookup
        return getRoundData(0);
    }
}
