// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import "src/InvestmentManager.sol";

    // struct LPValues {
    //     uint128 maxDeposit; // denominated in currency
    //     uint128 maxMint; // denominated in tranche tokens
    //     uint128 maxWithdraw; // denominated in currency
    //     uint128 maxRedeem; // denominated in tranche tokens
    //     uint128 remainingInvestOrder; // denominated in currency
    //     uint128 remainingRedeemOrder; // denominated in tranche tokens
    // }

contract MigratedInvestmentManager is InvestmentManager {
    // mapping(address investor => mapping(address liquidityPool => LPValues)) public orderbook;

    constructor(address _escrow, address _userEscrow, address _oldInvestmentManager, address[] memory investors, address[] memory liquidityPools) InvestmentManager(_escrow, _userEscrow) {
        InvestmentManager oldInvestmentManager = InvestmentManager(_oldInvestmentManager);
        gateway = oldInvestmentManager.gateway();
        poolManager = oldInvestmentManager.poolManager();

        // populate orderBook
        for(uint128 i = 0; i < investors.length; i++) {
            address investor = investors[i];
            for(uint128 j = 0; j < liquidityPools.length; j++) {
                address liquidityPool = liquidityPools[j];
                (uint128 maxDeposit, uint128 maxMint, uint128 maxWithdraw, uint128 maxRedeem, uint128 remainingInvestOrder, uint128 remainingRedeemOrder) = oldInvestmentManager.orderbook(investor, liquidityPool);
                orderbook[investor][liquidityPool] = LPValues({
                    maxDeposit: maxDeposit,
                    maxMint: maxMint,
                    maxWithdraw: maxWithdraw,
                    maxRedeem: maxRedeem,
                    remainingInvestOrder: remainingInvestOrder,
                    remainingRedeemOrder: remainingRedeemOrder
                });
            }
        }
    }
}