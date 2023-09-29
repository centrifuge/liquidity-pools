// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import {TestSetup} from "test/TestSetup.t.sol";
import {InvestorAccount} from "test/accounts/Investor.sol";
import "forge-std/Test.sol";
import "forge-std/console.sol";

interface ERC20Like {
    function balanceOf(address account) external view returns (uint256);
    function rely(address user) external;
}

contract InvestmentInvariants is TestSetup {
    InvestorAccount investorAccount;

    function setUp() public override {
        super.setUp();

        // TODO: right now, share and asset decimals are the same. We should also fuzz this
        deployLiquidityPool(1, erc20.decimals(), "", "", "1", 1, address(erc20));
        address liquidityPool = poolManager.getLiquidityPool(1, "1", address(erc20));

        excludeContract(address(liquidityPool));

        investorAccount =
            new InvestorAccount(1, "1", 1, liquidityPool, address(centrifugeChain), address(erc20), address(escrow));
        centrifugeChain.updateMember(1, "1", address(investorAccount), type(uint64).max);

        erc20.rely(address(investorAccount)); // rely to mint currency
        address share = poolManager.getTrancheToken(1, "1");
        root.relyContract(share, address(this));
        ERC20Like(share).rely(address(investorAccount)); // rely to mint tokens

        targetContract(address(investorAccount));
    }

    // invariant: tranche token balance <= trancheTokenPayoutSum
    function invariant_cannotReceiveMoreTrancheTokensThanPayout() external {
        assertLe(
            ERC20Like(poolManager.getTrancheToken(1, "1")).balanceOf(address(investorAccount)),
            investorAccount.totalTrancheTokensPaidOut()
        );
    }
}
