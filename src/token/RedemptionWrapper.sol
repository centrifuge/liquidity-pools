// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import {ERC20} from "src/token/ERC20.sol";
import {IERC20} from "src/interfaces/IERC20.sol";
import {IERC7540} from "src/interfaces/IERC7540.sol";
import {SafeTransferLib} from "src/libraries/SafeTransferLib.sol";

contract RedemptionWrapper is ERC20 {
    IERC7540 public immutable liquidityPool;
    IERC20 public immutable trancheToken;
    IERC20 public immutable asset;

    constructor(address liquidityPool_, uint8 decimals_) ERC20(decimals_) {
        liquidityPool = IERC7540(liquidityPool_);
        trancheToken = IERC20(liquidityPool.share());
        asset = IERC20(liquidityPool.asset());
    }

    function mint(address to, uint256 value) public override {
        require(trancheToken.transferFrom(msg.sender, address(this), value), "RedemptionWrapper/failed-transfer");
        super.mint(to, value);

        liquidityPool.requestRedeem(value, address(this), address(this), "");
    }

    function claim() public {
        liquidityPool.withdraw(liquidityPool.maxWithdraw(address(this)), address(this), address(this));
    }

    function burn(address from, uint256 value) public override {
        require(asset.balanceOf(address(this)) >= value, "RedemptionWrapper/insufficient-asset-balance");

        super.burn(from, value);
        SafeTransferLib.safeTransferFrom(address(asset), address(this), msg.sender, value);
    }
}
