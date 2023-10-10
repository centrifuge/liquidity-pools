// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import "src/InvestmentManager.sol";

interface RootLike {
    function relyContract(address, address) external;
    function denyContract(address, address) external;
    function rely(address) external;
    function deny(address) external;
}

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
                    uint128 maxMint,
                    uint256 depositPrice,
                    uint128 maxWithdraw,
                    uint256 redeemPrice,
                    uint128 remainingDepositRequest,
                    uint128 remainingRedeemRequest,
                    bool exists
                ) = oldInvestmentManager.investments(investor, liquidityPool);
                investments[investor][liquidityPool] = InvestmentState({
                    maxMint: maxMint,
                    depositPrice: depositPrice,
                    maxWithdraw: maxWithdraw,
                    redeemPrice: redeemPrice,
                    remainingDepositRequest: remainingDepositRequest,
                    remainingRedeemRequest: remainingRedeemRequest,
                    exists: exists
                });
            }
        }
    }
}
