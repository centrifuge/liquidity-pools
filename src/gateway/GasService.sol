// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import {Auth} from "src/Auth.sol";
import {IGasService} from "src/interfaces/gateway/IGasService.sol";
import {MathLib} from "src/libraries/MathLib.sol";
import {MessagesLib} from "src/libraries/MessagesLib.sol";

contract GasService is IGasService, Auth {
    using MathLib for uint256;

    uint80 roundId;
    uint256 updatedTime;
    /// @inheritdoc IGasService
    uint256 public price;
    /// @inheritdoc IGasService
    uint256 public messageCost;
    /// @inheritdoc IGasService
    uint256 public proofCost;

    constructor(uint256 messageCost_, uint256 proofCost_, uint256 price_) {
        messageCost = messageCost_;
        proofCost = proofCost_;
        price = price_;
        updatedTime = block.timestamp;
        roundId = 1;
    }

    /// @inheritdoc IGasService
    function file(bytes32 what, uint256 value) external auth {
        if (what == "messageCost") messageCost = value;
        if (what == "proofCost") proofCost = value;
        else revert("CentrifugeGasService/file-unrecognized-param");
        emit File(what, value);
    }

    /// @inheritdoc IGasService
    function updatePrice(uint256 value) external auth {
        price = value;
        roundId++;
        updatedTime = block.timestamp;
    }

    /// @inheritdoc IGasService
    function estimate(bytes calldata payload) public view returns (uint256) {
        if (MessagesLib.messageType(payload) == MessagesLib.Call.MessageProof) {
            return proofCost.mulDiv(price, 10 ** 18, MathLib.Rounding.Up);
        }
        return messageCost.mulDiv(price, 10 ** 18, MathLib.Rounding.Up);
    }
}
