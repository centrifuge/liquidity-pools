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
import {LiquidityPoolTest} from "test/LiquidityPool.t.sol";
import {PermissionlessRouter} from "test/mock/PermissionlessRouter.sol";
import {Root} from "src/Root.sol";
import {LiquidityPool} from "src/LiquidityPool.sol";

import {AxelarEVMScript} from "script/AxelarEVM.s.sol";
import {PermissionlessScript} from "script/Permissionless.s.sol";
import "forge-std/Test.sol";

interface ApproveLike {
    function approve(address, uint256) external;
}

contract DeployTest is Test {
    InvestmentManager investmentManager;
    Gateway gateway;
    Root root;
    MockHomeLiquidityPools mockLiquidityPools;
    RouterLike router;
    Escrow escrow;
    PauseAdmin pauseAdmin;
    DelayedAdmin delayedAdmin;
    TokenManager tokenManager;

    address DAI;
    address self;

    function setUp() public {
        // Run the AxelarEVM deploy script
        PermissionlessScript script = new PermissionlessScript();
        script.run();

        DAI = address(0x6B175474E89094C44Da98b954EedeAC495271d0F);

        investmentManager = script.investmentManager();
        gateway = script.gateway();
        root = script.root();
        escrow = script.escrow();
        pauseAdmin = script.pauseAdmin();
        delayedAdmin = script.delayedAdmin();
        tokenManager = script.tokenManager();

        RouterLike router = RouterLike(gateway.outgoingRouter());
        mockLiquidityPools = new MockHomeLiquidityPools(address(router));

        self = address(this);
    }

    function deployPoolAndTranche(
        uint64 poolId,
        bytes16 trancheId,
        string memory tokenName,
        string memory tokenSymbol,
        uint8 decimals,
        uint128 price,
        ERC20 erc20
    ) public returns (address) {
        uint64 validUntil = uint64(block.timestamp + 1000 days);

        vm.startPrank(address(gateway));
        investmentManager.addPool(poolId);
        investmentManager.addTranche(poolId, trancheId, tokenName, tokenSymbol, decimals, price);
        tokenManager.addCurrency(1, DAI);
        investmentManager.allowPoolCurrency(poolId, 1);
        vm.stopPrank();

        investmentManager.deployTranche(poolId, trancheId);
        address lPool = investmentManager.deployLiquidityPool(poolId, trancheId, address(erc20));
        return lPool;
    }

    function testDeployAndInvestRedeem(
        uint64 poolId,
        uint8 decimals,
        string memory tokenName,
        string memory tokenSymbol,
        bytes16 trancheId
    ) public {
        uint8 decimals = 6;
        uint128 price = 1e27;
        uint128 currencyId = 1;
        uint256 amount = 1000;
        uint64 validUntil = uint64(block.timestamp + 1000 days);
        // deployPoolAndTranche(poolId, trancheId, tokenName, tokenSymbol, decimals, price);
        DepositMint(
            poolId, decimals, tokenName, tokenSymbol, trancheId, price, currencyId, amount, validUntil, ERC20(DAI)
        );
    }

    function DepositMint(
        uint64 poolId,
        uint8 decimals,
        string memory tokenName,
        string memory tokenSymbol,
        bytes16 trancheId,
        uint128 price,
        uint128 currencyId,
        uint256 amount,
        uint64 validUntil,
        ERC20 erc20
    ) public {
        vm.assume(currencyId > 0);
        vm.assume(amount < type(uint128).max);
        vm.assume(amount > 1);
        vm.assume(validUntil >= block.timestamp);
        price = 2;

        address lPool_ = deployPoolAndTranche(poolId, trancheId, tokenName, tokenSymbol, decimals, price, erc20);
        // address lPool_ = deployLiquidityPool(poolId, decimals, tokenName, tokenSymbol, trancheId, price, currencyId, erc20);
        LiquidityPool lPool = LiquidityPool(lPool_);

        deal(address(erc20), self, amount);

        // will fail - user not member: can not receive trancheToken
        vm.expectRevert(bytes("InvestmentManager/not-a-member"));
        lPool.requestDeposit(amount, self);
        mockLiquidityPools.updateMember(poolId, trancheId, self, validUntil); // add user as member

        // // will fail - user did not give currency allowance to investmentManager
        vm.expectRevert(bytes("Dai/insufficient-allowance"));
        lPool.requestDeposit(amount, self);
        erc20.approve(address(investmentManager), amount); // add allowance

        lPool.requestDeposit(amount, self);

        // ensure funds are locked in escrow
        assertEq(erc20.balanceOf(address(escrow)), amount);
        assertEq(erc20.balanceOf(self), 0);

        // trigger executed collectInvest
        uint128 _currencyId = tokenManager.currencyAddressToId(address(erc20)); // retrieve currencyId
        uint128 trancheTokensPayout = uint128(amount) / price; // trancheTokenPrice = 2$
        mockLiquidityPools.isExecutedCollectInvest(
            poolId, trancheId, bytes32(bytes20(self)), _currencyId, uint128(amount), trancheTokensPayout
        );

        // assert deposit & mint values adjusted
        assertEq(lPool.maxMint(self), trancheTokensPayout); // max deposit
        assertEq(lPool.maxDeposit(self), amount); // max deposit
        // assert tranche tokens minted
        assertEq(lPool.balanceOf(address(escrow)), trancheTokensPayout);

        // deposit a share of the amount
        uint256 share = 2;
        lPool.deposit(amount / share, self); // mint hald the amount
        assertEq(lPool.balanceOf(self), trancheTokensPayout / share);
        assertEq(lPool.balanceOf(address(escrow)), trancheTokensPayout - trancheTokensPayout / share);
        assertEq(lPool.maxMint(self), trancheTokensPayout - trancheTokensPayout / share); // max deposit
        assertEq(lPool.maxDeposit(self), amount - amount / share); // max deposit

        // mint the rest
        lPool.mint(lPool.maxMint(self), self);
        assertEq(lPool.balanceOf(self), trancheTokensPayout - lPool.maxMint(self));
        assertTrue(lPool.balanceOf(address(escrow)) <= 1);
        assertTrue(lPool.maxMint(self) <= 1);
    }
}
