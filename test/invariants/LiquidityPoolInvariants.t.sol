// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import {TestSetup} from "test/TestSetup.t.sol";
import {InvestorHandler} from "test/invariants/handlers/Investor.sol";
import {EpochExecutorHandler} from "test/invariants/handlers/EpochExecutor.sol";
import {IERC7540} from "src/interfaces/IERC7540.sol";
import {IERC20} from "src/interfaces/IERC20.sol";
import "forge-std/Test.sol";
import "forge-std/console.sol";

interface LiquidityPoolLike is IERC7540 {
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

    bytes16 public constant TRANCHE_ID = "1";
    uint128 public constant CURRENCY_ID = 1;
    uint8 public constant RESTRICTION_SET = 1;

    address[] public pools;
    address[] public investors;

    mapping(uint64 poolId => InvestorHandler handler) investorHandlers;
    mapping(uint64 poolId => EpochExecutorHandler handler) epochExecutorHandlers;

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
            address pool = deployLiquidityPool(
                poolId, trancheTokenDecimals, RESTRICTION_SET, "", "", TRANCHE_ID, currencyId, currency
            );
            pools.push(pool);

            excludeContract(pool);
        }

        for (uint64 poolId; poolId < NUM_POOLS; ++poolId) {
            for (uint256 i; i < NUM_INVESTORS; ++i) {
                address investor = makeAddr(string(abi.encode("investor", i)));
                investors.push(investor);
                centrifugeChain.updateMember(poolId, TRANCHE_ID, investor, type(uint64).max);
            }

            address pool = pools[poolId];
            address currency = LiquidityPoolLike(pool).asset();
            InvestorHandler handler = new InvestorHandler(
                poolId,
                TRANCHE_ID,
                CURRENCY_ID,
                pool,
                address(centrifugeChain),
                currency,
                address(escrow),
                address(this)
            );
            investorHandlers[poolId] = handler;

            EpochExecutorHandler eeHandler =
                new EpochExecutorHandler(poolId, TRANCHE_ID, CURRENCY_ID, address(centrifugeChain), address(this));
            epochExecutorHandlers[poolId] = eeHandler;

            address share = poolManager.getTrancheToken(poolId, TRANCHE_ID);
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
                assertLe(
                    IERC20(pool.share()).balanceOf(investor),
                    handler.values(investor, "totalTrancheTokensPaidOutOnInvest")
                );
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
    function invariant_convertToAssetsEquivalence() external {
        for (uint64 poolId; poolId < NUM_POOLS; ++poolId) {
            LiquidityPoolLike pool = LiquidityPoolLike(pools[poolId]);

            // Does not hold if the price is 0
            if (pool.convertToAssets(1) == 0) return;

            if (pool.totalAssets() < type(uint128).max) {
                assertEq(pool.convertToAssets(IERC20(pool.share()).totalSupply()), pool.totalAssets());
            }
        }
    }

    // Invariant 4: convertToShares(totalAssets) == totalSupply
    function invariant_convertToSharesEquivalence() external {
        for (uint64 poolId; poolId < NUM_POOLS; ++poolId) {
            LiquidityPoolLike pool = LiquidityPoolLike(pools[poolId]);

            // Does not hold if the price is 0
            if (pool.convertToAssets(1) == 0) return;

            if (IERC20(pool.share()).totalSupply() < type(uint128).max) {
                assertEq(pool.convertToShares(pool.totalAssets()), IERC20(pool.share()).totalSupply());
            }
        }
    }

    // Invariant 5: lp.maxDeposit <= sum(requestDeposit)
    function invariant_maxDepositLeDepositRequest() external {
        for (uint64 poolId; poolId < NUM_POOLS; ++poolId) {
            LiquidityPoolLike pool = LiquidityPoolLike(pools[poolId]);
            InvestorHandler handler = investorHandlers[poolId];

            for (uint256 i; i < investors.length; ++i) {
                address investor = investors[i];
                assertLe(pool.maxDeposit(investor), handler.values(investor, "totalDepositRequested"));
            }
        }
    }

    // Invariant 6: lp.maxRedeem <= sum(requestRedeem) + sum(decreaseDepositRequest)
    // TODO: handle cancel behaviour
    function invariant_maxRedeemLeRedeemRequest() external {
        for (uint64 poolId; poolId < NUM_POOLS; ++poolId) {
            LiquidityPoolLike pool = LiquidityPoolLike(pools[poolId]);
            InvestorHandler handler = investorHandlers[poolId];

            for (uint256 i; i < investors.length; ++i) {
                address investor = investors[i];
                assertLe(
                    pool.maxRedeem(investor),
                    handler.values(investor, "totalRedeemRequested")
                        + handler.values(investor, "totalDecreaseDepositRequested")
                );
            }
        }
    }

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
