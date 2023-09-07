// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import {LiquidityPool} from "src/LiquidityPool.sol";
import {InvestmentManager} from "src/InvestmentManager.sol";

contract AtomicLiquidityPool {

    constructor(){}

    function deposit(uint256 assets, address receiver) public returns (uint256 shares) {
        // requestDeposit(assets, receiver);
        // investmentManager.handleExecutedCollectInvest(assets);
        // deposit(assets, receiver);
    }
}
