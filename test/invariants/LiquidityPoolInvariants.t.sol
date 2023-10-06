// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import {TestSetup} from "test/TestSetup.t.sol";
import {InvestorHandler} from "test/invariants/handlers/Investor.sol";
import {IERC4626} from "src/interfaces/IERC4626.sol";
import "forge-std/Test.sol";
import "forge-std/console.sol";

interface LiquidityPoolLike is IERC4626 {}

interface ERC20Like {
    function balanceOf(address account) external view returns (uint256);
    function rely(address user) external;
}

contract InvestmentInvariants is TestSetup {
    InvestorHandler investorHandler;
    LiquidityPoolLike liquidityPool;

    function setUp() public override {
        super.setUp();

        // TODO: right now, share and asset decimals are the same. We should also fuzz this
        deployLiquidityPool(1, erc20.decimals(), "", "", "1", 1, address(erc20));
        address liquidityPool_ = poolManager.getLiquidityPool(1, "1", address(erc20));
        liquidityPool = LiquidityPoolLike(liquidityPool_);

        excludeContract(liquidityPool_);

        investorHandler =
            new InvestorHandler(1, "1", 1, liquidityPool_, address(centrifugeChain), address(erc20), address(escrow));
        centrifugeChain.updateMember(1, "1", address(investorHandler), type(uint64).max);

        erc20.rely(address(investorHandler)); // rely to mint currency
        address share = poolManager.getTrancheToken(1, "1");
        root.relyContract(share, address(this));
        ERC20Like(share).rely(address(investorHandler)); // rely to mint tokens

        targetContract(address(investorHandler));
    }

    // Invariant 1: trancheToken.balanceOf[user] <= sum(tranchyTokenPayout)
    function invariant_cannotReceiveMoreTrancheTokensThanPayout() external {
        assertLe(liquidityPool.balanceOf(address(investorHandler)), investorHandler.totalTrancheTokensPaidOutOnInvest());
    }

    // Invariant 2: currency.balanceOf[user] <= sum(currencyPayout)
    function invariant_cannotReceiveMoreCurrencyThanPayout() external {
        assertLe(investorHandler.totalCurrencyReceived(), investorHandler.totalCurrencyPaidOutOnRedeem());
    }

    // Invariant 3: convertToAssets(totalSupply) == totalAssets
    function invariant_convertToAssetsEquivalence() external {
        if (liquidityPool.totalAssets() < type(uint128).max) {
            assertEq(liquidityPool.convertToAssets(liquidityPool.totalSupply()), liquidityPool.totalAssets());
        }
    }
}
