// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.26;

import {Auth} from "src/Auth.sol";
import {IGasService} from "src/interfaces/gateway/IGasService.sol";
import {MathLib} from "src/libraries/MathLib.sol";
import {BytesLib} from "src/libraries/BytesLib.sol";
import {MessagesLib} from "src/libraries/MessagesLib.sol";

contract GasService is IGasService, Auth {
    using MathLib for uint64;
    using MathLib for uint256;
    using BytesLib for bytes;

    /// @inheritdoc IGasService
    uint64 public proofCost;
    /// @inheritdoc IGasService
    uint64 public messageCost;
    /// @inheritdoc IGasService
    uint128 public gasPrice;
    /// @inheritdoc IGasService
    uint64 public lastUpdatedAt;
    /// @inheritdoc IGasService
    uint256 public tokenPrice;

    constructor(uint64 messageCost_, uint64 proofCost_, uint128 gasPrice_, uint256 tokenPrice_) {
        messageCost = messageCost_;
        proofCost = proofCost_;
        gasPrice = gasPrice_;
        tokenPrice = tokenPrice_;
        lastUpdatedAt = uint64(block.timestamp);

        wards[msg.sender] = 1;
        emit Rely(msg.sender);
    }

    /// @inheritdoc IGasService
    function file(bytes32 what, uint64 value) external auth {
        if (what == "messageCost") messageCost = value;
        else if (what == "proofCost") proofCost = value;
        else revert("GasService/file-unrecognized-param");
        emit File(what, value);
    }

    /// @inheritdoc IGasService
    function updateGasPrice(uint128 value, uint64 computedAt) external auth {
        require(value > 0, "GasService/price-cannot-be-zero");
        require(gasPrice != value, "GasService/same-price-already-set");
        require(lastUpdatedAt < computedAt, "GasService/cannot-update-price-with-backdate");
        gasPrice = value;
        lastUpdatedAt = computedAt;
        emit UpdateGasPrice(value, computedAt);
    }

    /// @inheritdoc IGasService
    function updateTokenPrice(uint256 value) external auth {
        tokenPrice = value;
        emit UpdateTokenPrice(value);
    }

    /// @inheritdoc IGasService
    function estimate(bytes calldata payload) public view returns (uint256) {
        uint256 denominator = 10 ** 18;
        uint256 totalCost;
        uint8 call = payload.toUint8(0);
        if (call == uint8(MessagesLib.Call.MessageProof)) {
            totalCost = proofCost.mulDiv(gasPrice, denominator, MathLib.Rounding.Up);
        } else {
            totalCost = messageCost.mulDiv(gasPrice, denominator, MathLib.Rounding.Up);
        }

        return totalCost.mulDiv(tokenPrice, denominator, MathLib.Rounding.Up);
    }

    /// @inheritdoc IGasService
    function shouldRefuel(address, bytes calldata) public pure returns (bool) {
        return true;
    }
}
