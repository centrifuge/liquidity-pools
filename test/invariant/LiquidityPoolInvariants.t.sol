// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import {BaseTest} from "test/BaseTest.sol";
import {InvestorHandler} from "test/invariant/handlers/Investor.sol";
import {EpochExecutorHandler} from "test/invariant/handlers/EpochExecutor.sol";
import {IERC7540} from "src/interfaces/IERC7540.sol";
import {IERC20} from "src/interfaces/IERC20.sol";
import "forge-std/Test.sol";

interface LiquidityPoolLike is IERC7540 {
    function asset() external view returns (address);
    function share() external view returns (address);
    function poolId() external view returns (uint64);
}

interface TrancheTokenLike {
    function restrictionManager() external view returns (address);
}

interface ERC20Like {
    function balanceOf(address account) external view returns (uint256);
    function rely(address user) external;
}

/// @dev Goal: Set up a global state where all external inputs are statefully
///      fuzzed through handlers, while the internal inputs controlled by
///      actors on Centrifuge Chain is randomly configured but not fuzzed.
contract InvestmentInvariants is BaseTest {
    uint256 public constant NUM_CURRENCIES = 1;
    uint256 public constant NUM_POOLS = 1;
    uint256 public constant NUM_INVESTORS = 1;

    bytes16 public constant TRANCHE_ID = "1";
    uint128 public constant CURRENCY_ID = 1;
    uint8 public constant RESTRICTION_SET = 1;

    mapping(uint128 => address) public currencies;
    address[] public liquidityPools;
    address[] public investors;

    mapping(uint64 poolId => InvestorHandler handler) investorHandlers;
    mapping(uint64 poolId => EpochExecutorHandler handler) epochExecutorHandlers;

    // Key-value store for shadow variables
    mapping(address entity => mapping(string key => uint256 value)) public shadowVariables;

    function setUp() public override {
        super.setUp();

        // Generate random investment currencies
        for (uint128 currencyId = 1; currencyId < NUM_CURRENCIES + 1; ++currencyId) {
            uint8 currencyDecimals = _randomUint8(1, 18);

            address currency = address(
                _newErc20(
                    string(abi.encode("currency", currencyId)),
                    string(abi.encode("currency", currencyId)),
                    currencyDecimals
                )
            );
            currencies[currencyId] = currency;
            excludeContract(currency);
        }

        // Generate random liquidity pools
        // TODO: multiple chains and allowing transfers between chains
        for (uint128 currencyId = 1; currencyId < NUM_CURRENCIES + 1; ++currencyId) {
            for (uint64 poolId; poolId < NUM_POOLS; ++poolId) {
                uint8 trancheTokenDecimals = _randomUint8(1, 18);
                address lpool = deployLiquidityPool(
                    poolId,
                    trancheTokenDecimals,
                    RESTRICTION_SET,
                    "",
                    "",
                    TRANCHE_ID,
                    currencyId,
                    currencies[currencyId]
                );
                liquidityPools.push(lpool);
                excludeContract(lpool);
                excludeContract(LiquidityPoolLike(lpool).share());
                excludeContract(TrancheTokenLike(LiquidityPoolLike(lpool).share()).restrictionManager());
            }
        }

        // Generate investor accounts
        for (uint256 i; i < NUM_INVESTORS; ++i) {
            address investor = makeAddr(string(abi.encode("investor", _uint256ToString(i))));
            investors.push(investor);

            for (uint64 poolId; poolId < NUM_POOLS; ++poolId) {
                centrifugeChain.updateMember(poolId, TRANCHE_ID, investor, type(uint64).max);
            }
        }

        // Set up investor and epoch executor handlers
        // - For each unique pool and each unique currency, 1 LP.
        // - Just 1 tranche per pool
        // - NUM_INVESTORS per LP.
        for (uint64 lpoolId; lpoolId < liquidityPools.length; ++lpoolId) {
            LiquidityPoolLike lpool = LiquidityPoolLike(liquidityPools[lpoolId]);

            address currency = lpool.asset();
            InvestorHandler handler = new InvestorHandler(
                lpool.poolId(),
                TRANCHE_ID,
                CURRENCY_ID,
                address(lpool),
                address(centrifugeChain),
                currency,
                address(escrow),
                address(this)
            );
            investorHandlers[lpoolId] = handler;

            EpochExecutorHandler eeHandler = new EpochExecutorHandler(
                lpool.poolId(), TRANCHE_ID, CURRENCY_ID, address(centrifugeChain), address(this)
            );
            epochExecutorHandlers[lpoolId] = eeHandler;

            address share = poolManager.getTrancheToken(lpool.poolId(), TRANCHE_ID);
            root.relyContract(share, address(this));
            ERC20Like(currency).rely(address(handler)); // rely to mint currency
            ERC20Like(share).rely(address(handler)); // rely to mint tokens

            targetContract(address(handler));
            targetContract(address(eeHandler));
        }
    }

    // Invariant 1: trancheToken.balanceOf[user] <= sum(trancheTokenPayout)
    function invariant_cannotReceiveMoreTrancheTokensThanPayout() external {
        for (uint64 lpoolId; lpoolId < liquidityPools.length; ++lpoolId) {
            LiquidityPoolLike lpool = LiquidityPoolLike(liquidityPools[lpoolId]);

            for (uint256 i; i < investors.length; ++i) {
                address investor = investors[i];
                assertLe(
                    IERC20(lpool.share()).balanceOf(investor),
                    getShadowVar(investor, "totalTrancheTokensPaidOutOnInvest")
                );
            }
        }
    }

    // Invariant 2: currency.balanceOf[user] <= sum(currencyPayout for each redemption)
    //              + sum(currencyPayout for each decreased investment)
    function invariant_cannotReceiveMoreCurrencyThanPayout() external {
        for (uint64 lpoolId; lpoolId < liquidityPools.length; ++lpoolId) {
            for (uint256 i; i < investors.length; ++i) {
                address investor = investors[i];
                assertLe(
                    getShadowVar(investor, "totalCurrencyReceived"),
                    getShadowVar(investor, "totalCurrencyPaidOutOnRedeem")
                        + getShadowVar(investor, "totalCurrencyPaidOutOnDecreaseInvest")
                );
            }
        }
    }

    // Invariant 3: convertToAssets(totalSupply) == totalAssets
    function invariant_convertToAssetsEquivalence() external {
        for (uint64 lpoolId; lpoolId < liquidityPools.length; ++lpoolId) {
            LiquidityPoolLike lpool = LiquidityPoolLike(liquidityPools[lpoolId]);

            // Does not hold if the price is 0
            if (lpool.convertToAssets(1) == 0) return;

            if (lpool.totalAssets() < type(uint128).max) {
                assertEq(lpool.convertToAssets(IERC20(lpool.share()).totalSupply()), lpool.totalAssets());
            }
        }
    }

    // Invariant 4: convertToShares(totalAssets) == totalSupply
    function invariant_convertToSharesEquivalence() external {
        for (uint64 lpoolId; lpoolId < liquidityPools.length; ++lpoolId) {
            LiquidityPoolLike lpool = LiquidityPoolLike(liquidityPools[lpoolId]);

            // Does not hold if the price is 0
            if (lpool.convertToAssets(1) == 0) return;

            if (IERC20(lpool.share()).totalSupply() < type(uint128).max) {
                assertEq(lpool.convertToShares(lpool.totalAssets()), IERC20(lpool.share()).totalSupply());
            }
        }
    }

    // Invariant 5: lp.maxDeposit <= sum(requestDeposit)
    // function invariant_maxDepositLeDepositRequest() external {
    //     for (uint64 lpoolId; lpoolId < liquidityPools.length; ++lpoolId) {
    //         LiquidityPoolLike lpool = LiquidityPoolLike(liquidityPools[lpoolId]);
    //         InvestorHandler handler = investorHandlers[lpoolId];

    //         for (uint256 i; i < investors.length; ++i) {
    //             address investor = investors[i];
    //             assertLe(lpool.maxDeposit(investor), getShadowVar(investor, "totalDepositRequested"));
    //         }
    //     }
    // }

    // Invariant 6: lp.maxRedeem <= sum(requestRedeem) + sum(decreaseDepositRequest)
    // TODO: handle cancel behaviour
    // function invariant_maxRedeemLeRedeemRequest() external {
    //     for (uint64 lpoolId; lpoolId < liquidityPools.length; ++lpoolId) {
    //         LiquidityPoolLike lpool = LiquidityPoolLike(liquidityPools[lpoolId]);
    //         InvestorHandler handler = investorHandlers[lpoolId];

    //         for (uint256 i; i < investors.length; ++i) {
    //             address investor = investors[i];
    //             assertLe(
    //                 lpool.maxRedeem(investor),
    //                 getShadowVar(investor, "totalRedeemRequested")
    //                     + getShadowVar(investor, "totalDecreaseDepositRequested")
    //             );
    //         }
    //     }
    // }

    // Invariant 7: lp.depositPrice <= max(fulfillment price)
    function invariant_depositPriceLtMaxFulfillmentPrice() external {
        for (uint64 lpoolId; lpoolId < liquidityPools.length; ++lpoolId) {
            LiquidityPoolLike lpool = LiquidityPoolLike(liquidityPools[lpoolId]);

            for (uint256 i; i < investors.length; ++i) {
                address investor = investors[i];
                (, uint256 depositPrice,,,,,) = investmentManager.investments(address(lpool), investor);

                assertLe(depositPrice, getShadowVar(investor, "maxDepositFulfillmentPrice"));
            }
        }
    }

    // Invariant 8: lp.redeemPrice <= max(fulfillment price)
    function invariant_redeemPriceLtMaxFulfillmentPrice() external {
        for (uint64 lpoolId; lpoolId < liquidityPools.length; ++lpoolId) {
            LiquidityPoolLike lpool = LiquidityPoolLike(liquidityPools[lpoolId]);

            for (uint256 i; i < investors.length; ++i) {
                address investor = investors[i];
                (,,, uint256 redeemPrice,,,) = investmentManager.investments(address(lpool), investor);

                assertLe(redeemPrice, getShadowVar(investor, "maxRedeemFulfillmentPrice"));
            }
        }
    }

    function getShadowVar(address entity, string memory key) public view returns (uint256) {
        return shadowVariables[entity][key];
    }

    function setShadowVar(address entity, string memory key, uint256 value) public {
        shadowVariables[entity][key] = value;
    }

    function numInvestors() public view returns (uint256) {
        return investors.length;
    }

    function _randomUint8(uint8 minValue, uint8 maxValue) internal view returns (uint8) {
        uint256 nonce = 1;

        if (maxValue == 1) {
            return 1;
        }

        uint8 value = uint8(uint256(keccak256(abi.encodePacked(block.timestamp, self, nonce))) % (maxValue - minValue));
        return value + minValue;
    }
}
