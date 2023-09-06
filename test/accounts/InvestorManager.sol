// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.18;
pragma abicoder v2;

import {TestSetup} from "test/TestSetup.t.sol";

import "forge-std/Test.sol";

interface ERC20Like {
    function approve(address spender, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}

contract InvestorManager is TestSetup {
    // This handler only uses a single pool, tranche and user combination
    uint64 public fixedPoolId = 1;
    bytes16 public fixedTrancheId = "1";
    uint128 public fixedCurrencyId = 1;
    address public fixedToken;

    // Investor initially holds 10M tranche tokens on Centrifuge Chain
    uint128 public investorBalanceOnCentrifugeChain = 10_000_000 * 10 ** 18;

    uint256 public totalTransferredIn;
    uint256 public totalTransferredOut;
    address[] public allInvestors;
    mapping(address => uint256) public investorTransferredIn;
    mapping(address => uint256) public investorTransferredOut;

    constructor() {
        setUp();
        deployLiquidityPool(fixedPoolId, 18, "", "", fixedTrancheId, fixedCurrencyId, address(erc20));
        homePools.updateMember(fixedPoolId, fixedTrancheId, address(this), type(uint64).max);
        fixedToken = poolManager.getTrancheToken(fixedPoolId, fixedTrancheId);
        allInvestors.push(address(this));
    }

    function addInvestor(uint64 poolId, bytes16 trancheId, address investor, uint128 amount) public {
        homePools.updateMember(poolId, trancheId, investor, type(uint64).max);
        allInvestors.push(investor);
    }

    function transferIn(uint256 investorIndex, uint256 amount) public {
        investorIndex = bound(investorIndex, 0, allInvestors.length - 1);
        address investor = allInvestors[investorIndex];
        amount = bound(amount, 0, uint256(investorBalanceOnCentrifugeChain));
        homePools.incomingTransferTrancheTokens(fixedPoolId, fixedTrancheId, 1, investor, uint128(amount));

        investorBalanceOnCentrifugeChain -= uint128(amount);
        totalTransferredIn += amount;
        investorTransferredIn[investor] += amount;
    }

    function transferOut(uint256 investorIndex, uint256 amount) public {
        investorIndex = bound(investorIndex, 0, allInvestors.length - 1);
        address investor = allInvestors[investorIndex];
        amount = bound(amount, 0, ERC20Like(fixedToken).balanceOf(investor));
        vm.startPrank(investor);
        ERC20Like(fixedToken).approve(address(poolManager), amount);
        poolManager.transferTrancheTokensToCentrifuge(fixedPoolId, fixedTrancheId, "1", uint128(amount));
        vm.stopPrank();

        investorBalanceOnCentrifugeChain += uint128(amount);
        totalTransferredOut += amount;
    }

    function allInvestorsLength() public view returns (uint256) {
        return allInvestors.length;
    }
}
