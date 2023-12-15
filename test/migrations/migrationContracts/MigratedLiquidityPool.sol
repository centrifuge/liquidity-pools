// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import "src/LiquidityPool.sol";

contract MigratedLiquidityPool is LiquidityPool {
    constructor(
        uint64 poolId_,
        bytes16 trancheId_,
        address asset_,
        address share_,
        address escrow_,
        address investmentManager_
    ) LiquidityPool(poolId_, trancheId_, asset_, share_, escrow_, investmentManager_) {}
}
