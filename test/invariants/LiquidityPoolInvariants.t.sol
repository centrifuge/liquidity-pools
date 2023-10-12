// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import {TestSetup} from "test/TestSetup.t.sol";
import {InvestorHandler} from "test/invariants/handlers/Investor.sol";
import {IERC4626} from "src/interfaces/IERC4626.sol";
import "forge-std/Test.sol";
import "forge-std/console.sol";

interface LiquidityPoolLike is IERC4626 {
    function latestPrice() external view returns (uint256);
}

interface ERC20Like {
    function balanceOf(address account) external view returns (uint256);
    function rely(address user) external;
}

contract InvestmentInvariants is TestSetup {
    uint256 public constant NUM_POOLS = 1;
    uint256 public constant NUM_CURRENCIES = 1;
    uint256 public constant NUM_INVESTORS = 2;

    InvestorHandler investorHandler;
    LiquidityPoolLike liquidityPool;

    address[] public pools;
    address[] public investors;
    address[] public currencies;

    function setUp() public override {
        super.setUp();

        // TODO: right now, share and asset decimals are the same. We should also fuzz this
        deployLiquidityPool(1, erc20.decimals(), "", "", "1", 1, address(erc20));
        address liquidityPool_ = poolManager.getLiquidityPool(1, "1", address(erc20));
        liquidityPool = LiquidityPoolLike(liquidityPool_);

        excludeContract(liquidityPool_);

        for (uint256 i; i < NUM_INVESTORS; ++i) {
            address investor = makeAddr(string(abi.encode("investor", i)));
            investors.push(investor);
            centrifugeChain.updateMember(1, "1", investor, type(uint64).max);
        }

        investorHandler =
        new InvestorHandler(1, "1", 1, liquidityPool_, address(centrifugeChain), address(erc20), address(escrow), address(this));

        erc20.rely(address(investorHandler)); // rely to mint currency
        address share = poolManager.getTrancheToken(1, "1");
        root.relyContract(share, address(this));
        ERC20Like(share).rely(address(investorHandler)); // rely to mint tokens

        targetContract(address(investorHandler));
    }

    // Invariant 1: trancheToken.balanceOf[user] <= sum(tranchyTokenPayout)
    function invariant_cannotReceiveMoreTrancheTokensThanPayout() external {
        for (uint256 i; i < investors.length; ++i) {
            address investor = investors[i];
            (,,, uint256 totalTrancheTokensPaidOutOnInvest,,,) = investorHandler.investorState(investor);
            assertLe(liquidityPool.balanceOf(investor), totalTrancheTokensPaidOutOnInvest);
        }
    }

    // Invariant 2: currency.balanceOf[user] <= sum(currencyPayout)
    function invariant_cannotReceiveMoreCurrencyThanPayout() external {
        for (uint256 i; i < investors.length; ++i) {
            address investor = investors[i];
            (,, uint256 totalCurrencyReceived,,, uint256 totalCurrencyPaidOutOnRedeem,) =
                investorHandler.investorState(investor);
            assertLe(totalCurrencyReceived, totalCurrencyPaidOutOnRedeem);
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
    function invariant_maxDepositLeDepositRequest() external {
        for (uint256 i; i < investors.length; ++i) {
            address investor = investors[i];
            (uint256 totalDepositRequested,,,,,,) = investorHandler.investorState(investor);
            assertLe(liquidityPool.maxDeposit(investor), totalDepositRequested);
        }
    }

    // Invariant 6: lp.maxRedeem <= sum(requestRedeem)
    function invariant_maxRedeemLeRedeemRequest() external {
        for (uint256 i; i < investors.length; ++i) {
            address investor = investors[i];
            (, uint256 totalRedeemRequested,,,,,) = investorHandler.investorState(investor);
            assertLe(liquidityPool.maxRedeem(investor), totalRedeemRequested);
        }
    }

    function numInvestors() public view returns (uint256) {
        return investors.length;
    }
}
