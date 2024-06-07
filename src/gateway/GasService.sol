// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import {Auth} from "src/Auth.sol";
import {IAggregatorV3} from "src/interfaces/IAggregatorV3.sol";
import {MathLib} from "src/libraries/MathLib.sol";
import {MessagesLib} from "src/libraries/MessagesLib.sol";

contract GasService is IAggregatorV3, Auth {
    using MathLib for uint256;

    uint8 public constant decimals = 18;
    string public constant description = "CFG/ETH price feed";
    uint256 public constant version = 1;

    uint80 roundId;
    uint256 updatedTime;
    uint256 price;
    uint256 messageCost;
    uint256 proofCost;

    event File(bytes32 what, uint256 value);

    constructor(uint256 messageCost_, uint256 proofCost_, uint256 price_) {
        messageCost = messageCost_;
        proofCost = proofCost_;
        price = price_;
        updatedTime = block.timestamp;
        roundId = 1;
    }

    function file(bytes32 what, uint256 value) external auth {
        if (what == "messageCost") messageCost = value;
        if (what == "proofCost") proofCost = value;
        else revert("CentrifugeGasService/file-unrecognized-param");
        emit File(what, value);
    }

    function updatePrice(uint256 value) external auth {
        price = value;
        roundId++;
        updatedTime = block.timestamp;
    }

    function estimate(bytes calldata payload) public view returns (uint256) {
        if (MessagesLib.messageType(payload) == MessagesLib.Call.MessageProof) {
            return proofCost.mulDiv(price, 10 ** 18);
        }
        return messageCost.mulDiv(price, 10 ** 18);
    }

    function getRoundData(uint80) public view returns (uint80, int256, uint256, uint256) {
        return (roundId, int256(price), updatedTime, updatedTime);
    }

    function latestRoundData() public view returns (uint80, int256, uint256, uint256) {
        // Current version doesn't suport different rounds id lookup
        return getRoundData(0);
    }
}
