// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import {TestSetup} from "test/TestSetup.t.sol";
import {InvestorHandler} from "test/invariants/handlers/Investor.sol";
import {IERC4626} from "src/interfaces/IERC4626.sol";
import "forge-std/Test.sol";
import "forge-std/console.sol";

interface LiquidityPoolLike is IERC4626 {
    function latestPrice() external view returns (uint256);
    function asset() external view returns (address);
}

interface ERC20Like {
    function balanceOf(address account) external view returns (uint256);
    function rely(address user) external;
}

contract InvestmentInvariants is TestSetup {
    uint256 public constant NUM_POOLS = 1;
    uint256 public constant NUM_INVESTORS = 2;

    address[] public pools;
    address[] public investors;

    mapping(uint64 poolId => InvestorHandler handler) investorHandlers;

    function setUp() public override {
        super.setUp();

        for (uint64 poolId; poolId < NUM_POOLS; ++poolId) {
            uint8 trancheTokenDecimals = uint8(1 + _random(17, 1)); // 1-18
            uint8 currencyDecimals = uint8(1 + _random(17, 1)); // 1-18

            address currency = address(
                _newErc20(
                    string(abi.encode("currency", poolId)), string(abi.encode("currency", poolId)), currencyDecimals
                )
            );
            uint128 currencyId = poolId + 1;
            address pool = deployLiquidityPool(poolId, trancheTokenDecimals, 1, "", "", "1", currencyId, currency);
            pools.push(pool);

            excludeContract(pool);
        }

        for (uint64 poolId; poolId < NUM_POOLS; ++poolId) {
            for (uint256 i; i < NUM_INVESTORS; ++i) {
                address investor = makeAddr(string(abi.encode("investor", i)));
                investors.push(investor);
                centrifugeChain.updateMember(poolId, "1", investor, type(uint64).max);
            }

            address pool = pools[poolId];
            address currency = LiquidityPoolLike(pool).asset();
            InvestorHandler handler =
            new InvestorHandler(poolId, "1", 1, pool, address(centrifugeChain), currency, address(escrow), address(this));

            investorHandlers[poolId] = handler;

            address share = poolManager.getTrancheToken(poolId, "1");
            root.relyContract(share, address(this));
            ERC20Like(currency).rely(address(handler)); // rely to mint currency
            ERC20Like(share).rely(address(handler)); // rely to mint tokens

            targetContract(address(handler));
        }
    }

    // Invariant 1: trancheToken.balanceOf[user] <= sum(tranchyTokenPayout)
    function invariant_cannotReceiveMoreTrancheTokensThanPayout() external {
        for (uint64 poolId; poolId < NUM_POOLS; ++poolId) {
            LiquidityPoolLike pool = LiquidityPoolLike(pools[poolId]);
            InvestorHandler handler = investorHandlers[poolId];

            for (uint256 i; i < investors.length; ++i) {
                address investor = investors[i];
                assertLe(pool.balanceOf(investor), handler.values(investor, "totalTrancheTokensPaidOutOnInvest"));
            }
        }
    }

    // Invariant 2: currency.balanceOf[user] <= sum(currencyPayout for each redemption)
    //              + sum(currencyPayout for each decreased investment)
    function invariant_cannotReceiveMoreCurrencyThanPayout() external {
        for (uint64 poolId; poolId < NUM_POOLS; ++poolId) {
            InvestorHandler handler = investorHandlers[poolId];

            for (uint256 i; i < investors.length; ++i) {
                address investor = investors[i];
                assertLe(
                    handler.values(investor, "totalCurrencyReceived"),
                    handler.values(investor, "totalCurrencyPaidOutOnRedeem")
                        + handler.values(investor, "totalCurrencyPaidOutOnDecreaseInvest")
                );
            }
        }
    }

    // Invariant 3: convertToAssets(totalSupply) == totalAssets
    // function invariant_convertToAssetsEquivalence() external {
    //     // Does not hold if the price is 0
    //     if (liquidityPool.latestPrice() == 0) return;

    //     if (liquidityPool.totalAssets() < type(uint128).max) {
    //         assertEq(liquidityPool.convertToAssets(liquidityPool.totalSupply()), liquidityPool.totalAssets());
    //     }
    // }

    // Invariant 4: convertToShares(totalAssets) == totalSupply
    // function invariant_convertToSharesEquivalence() external {
    //     // Does not hold if the price is 0
    //     if (liquidityPool.latestPrice() == 0) return;

    //     if (liquidityPool.totalSupply() < type(uint128).max) {
    //         assertEq(liquidityPool.convertToShares(liquidityPool.totalAssets()), liquidityPool.totalSupply());
    //     }
    // }

    // Invariant 5: lp.maxDeposit <= sum(requestDeposit)
    // function invariant_maxDepositLeDepositRequest() external {
    //     for (uint64 poolId; poolId < NUM_POOLS; ++poolId) {
    //         LiquidityPoolLike pool = LiquidityPoolLike(pools[poolId]);
    //         InvestorHandler handler = investorHandlers[poolId];

    //         for (uint256 i; i < investors.length; ++i) {
    //             address investor = investors[i];
    //             (uint256 totalDepositRequested,,,,,,,,,) = handler.investorState(investor);
    //             assertLe(pool.maxDeposit(investor), totalDepositRequested);
    //         }
    //     }
    // }

    // Invariant 6: lp.maxRedeem <= sum(requestRedeem)
    // function invariant_maxRedeemLeRedeemRequest() external {
    //     for (uint64 poolId; poolId < NUM_POOLS; ++poolId) {
    //         LiquidityPoolLike pool = LiquidityPoolLike(pools[poolId]);
    //         InvestorHandler handler = investorHandlers[poolId];

    //         for (uint256 i; i < investors.length; ++i) {
    //             address investor = investors[i];
    //             (, uint256 totalRedeemRequested,,,,,,,,) = handler.investorState(investor);
    //             assertLe(pool.maxRedeem(investor), totalRedeemRequested);
    //         }
    //     }
    // }

    function numInvestors() public view returns (uint256) {
        return investors.length;
    }

    function _random(uint256 maxValue, uint256 nonce) internal view returns (uint256) {
        if (maxValue == 1) {
            return maxValue;
        }
        uint256 randomnumber = uint256(keccak256(abi.encodePacked(block.timestamp, self, nonce))) % (maxValue - 1);
        return randomnumber + 1;
    }
}
