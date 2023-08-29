// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.18;
pragma abicoder v2;

import {InvestmentManager, Pool, Tranche} from "src/InvestmentManager.sol";
import {Gateway, RouterLike} from "src/gateway/Gateway.sol";
import {MockHomeLiquidityPools} from "test/mock/MockHomeLiquidityPools.sol";
import {Escrow} from "src/Escrow.sol";
import {PauseAdmin} from "src/admins/PauseAdmin.sol";
import {DelayedAdmin} from "src/admins/DelayedAdmin.sol";
import {MockXcmRouter} from "test/mock/MockXcmRouter.sol";
import {TokenManager} from "src/TokenManager.sol";
import {ERC20} from "src/token/ERC20.sol";
import {TrancheToken} from "src/token/Tranche.sol";

import {AxelarEVMScript} from "script/AxelarEVM.s.sol";
import "forge-std/Test.sol";

interface ApproveLike {
    function approve(address, uint256) external;
}

contract MigrationsTest is Test {
    InvestmentManager investmentManager;
    Gateway gateway;
    MockHomeLiquidityPools mockLiquidityPools;
    Escrow escrow;
    PauseAdmin pauseAdmin;
    DelayedAdmin delayedAdmin;
    TokenManager tokenManager;

    address DAI;
    address investor;

    function setUp() public {
        DAI = address(0x6B175474E89094C44Da98b954EedeAC495271d0F);
        investor = address(0xFED);
        
        AxelarEVMScript script = new AxelarEVMScript();
        script.run();
        investmentManager = script.investmentManager();
        gateway = script.gateway();
        escrow = script.escrow();
        pauseAdmin = script.pauseAdmin();
        delayedAdmin = script.delayedAdmin();
        tokenManager = script.tokenManager();

        RouterLike outgoingRouter = RouterLike(gateway.outgoingRouter());
        mockLiquidityPools = new MockHomeLiquidityPools(address(outgoingRouter));
    }

    function deployPoolAndTranche(
        InvestmentManager activeInvestmentManager,
        MockXcmRouter activeMockXcmRouter,
        uint64 poolId,
        bytes16 trancheId,
        string memory tokenName,
        string memory tokenSymbol,
        uint8 decimals,
        uint128 price
    ) public {
        uint64 validUntil = uint64(block.timestamp + 1000 days);

        // deploy pool and tranche
        tokenManager.addCurrency(1, DAI);
        activeInvestmentManager.addPool(poolId);
        activeInvestmentManager.addTranche(poolId, trancheId, tokenName, tokenSymbol, decimals, price);
        activeInvestmentManager.deployTranche(poolId, trancheId);
        activeInvestmentManager.allowPoolCurrency(poolId, 1);
        activeInvestmentManager.deployLiquidityPool(poolId, trancheId, DAI);

        // add member
        tokenManager.updateMember(poolId, trancheId, investor, validUntil);
    }

    function runFullInvestRedeemCycle(
        InvestmentManager activeInvestmentManager,
        uint64 poolId,
        bytes16 trancheId,
        string memory tokenName,
        string memory tokenSymbol
    ) public {
        address _token = activeInvestmentManager.getTrancheToken(poolId, trancheId);

        // deal fake investor fake DAI and add allowance to escrow
        deal(DAI, investor, 1000);
        vm.prank(investor);
        ApproveLike(DAI).approve(address(activeInvestmentManager), 1000);
        // assertEq(ERC20(DAI).balanceOf(user), 1000);
        // TODO: activeInvestmentManager.requestDeposit(1000)

        // increase invest order and decrease by a smaller amount
        vm.startPrank(investor);
        activeInvestmentManager.increaseInvestOrder(poolId, trancheId, DAI, 1000);
        assertEq(ERC20(DAI).balanceOf(investor), 0);
        activeInvestmentManager.decreaseInvestOrder(poolId, trancheId, DAI, 100);
        vm.stopPrank();
        mockLiquidityPools.incomingExecutedDecreaseInvestOrder(poolId, trancheId, investor, 1, 100, 900); // TODO: Not implemeted yet
        // assertEq(ERC20(DAI).balanceOf(address(escrow)), 100);

        // Assume bot has triggered epoch execution. Then we can collect tranche tokens
        uint128 _price = 10 ** _token.decimals();
        vm.prank(investor);
        activeInvestmentManager.collectInvest(poolId, trancheId);
        uint128 trancheAmount = uint128(900 * _price / 10 ** uint128(_token.decimals()));
        mockLiquidityPools.incomingExecutedCollectInvest(poolId, trancheId, investor, 1, 0, 900, trancheAmount); // TODO: Not implemeted yet
        // TODO: activeInvestmentManager.deposit(1000)
        // assertEq(ERC20(token_).balanceOf(investor), trancheAmount);

        // time passes
        vm.warp(100 days);
        mockLiquidityPools.updateTokenPrice(poolId, trancheId, _price * 2);
        (, _price,,,,) = activeInvestmentManager.tranches(poolId, trancheId);

        // investor submits redeem order
        // TODO: activeInvestmentManager.requestRedeem(trancheAmount)
        vm.prank(investor);
        activeInvestmentManager.increaseRedeemOrder(poolId, trancheId, DAI, trancheAmount);
        // assertEq(ERC20(token_).balanceOf(investor), 0);

        //bot executs epoch, and investor redeems
        vm.prank(investor);
        activeInvestmentManager.collectRedeem(poolId, trancheId);
        uint128 daiAmount = uint128(trancheAmount * _price / 10 ** uint128(_token.decimals()));
        mockLiquidityPools.incomingExecutedCollectRedeem(poolId, trancheId, investor, 1, daiAmount, 0, 0); // TODO: Not implemeted yet
            // TODO: activeInvestmentManager.redeem(trancheAmount)
            // assertEq(ERC20(DAI).balanceOf(investor), daiAmount);
            // assertEq(ERC20(token).balanceOf(investor), 0);
    }

    function adminTest(address pauseAdmin, address delayedAdmin, address gateway) public {
        PauseAdmin(pauseAdmin).pause();
        assertTrue(Gateway(gateway).paused());
        PauseAdmin(pauseAdmin).unpause();
        assertFalse(Gateway(gateway).paused());
        address fakeSpell = address(0xBEEF);
        DelayedAdmin(delayedAdmin).schedule(fakeSpell);
        assertEq(Gateway(gateway).relySchedule(fakeSpell), block.timestamp + 48 hours);
        DelayedAdmin(delayedAdmin).cancelSchedule(fakeSpell);
        assertEq(Gateway(gateway).relySchedule(fakeSpell), 0);
    }

    function testDeploy() public {
        deployPoolAndTranche(investmentManager, mockLiquidityPools, 1, bytes16(0x123), "Some Token", "ST", 6, 1e27);
        runFullInvestRedeemCycle(investmentManager, mockLiquidityPools, 1, bytes16(0x123), "Some Token", "ST");
    }
}