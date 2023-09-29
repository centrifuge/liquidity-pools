// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import "src/InvestmentManager.sol";

contract MigratedInvestmentManager is InvestmentManager {
    /// @param investors The investors to migrate.
    /// @param liquidityPools The liquidity pools to migrate.
    constructor(
        address _escrow,
        address _userEscrow,
        address _oldInvestmentManager,
        address[] memory investors,
        address[] memory liquidityPools
    ) InvestmentManager(_escrow, _userEscrow) {
        InvestmentManager oldInvestmentManager = InvestmentManager(_oldInvestmentManager);
        gateway = oldInvestmentManager.gateway();
        poolManager = oldInvestmentManager.poolManager();

        for (uint128 i = 0; i < investors.length; i++) {
            address investor = investors[i];
            for (uint128 j = 0; j < liquidityPools.length; j++) {
                address liquidityPool = liquidityPools[j];
                (
                    uint128 maxDeposit,
                    uint128 maxMint,
                    uint128 maxWithdraw,
                    uint128 maxRedeem,
                    uint128 remainingInvestOrder,
                    uint128 remainingRedeemOrder
                ) = oldInvestmentManager.orderbook(investor, liquidityPool);
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
