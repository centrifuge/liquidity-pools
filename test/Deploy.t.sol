// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import {InvestmentManager} from "src/InvestmentManager.sol";
import {Gateway} from "src/gateway/Gateway.sol";
import {MockCentrifugeChain} from "test/mock/MockCentrifugeChain.sol";
import {Escrow} from "src/Escrow.sol";
import {PauseAdmin} from "src/admins/PauseAdmin.sol";
import {DelayedAdmin} from "src/admins/DelayedAdmin.sol";
import {MockRouter} from "test/mock/MockRouter.sol";
import {PoolManager, Pool, Tranche} from "src/PoolManager.sol";
import {ERC20} from "src/token/ERC20.sol";
import {TrancheToken} from "src/token/Tranche.sol";
import {LiquidityPoolTest} from "test/LiquidityPool.t.sol";
import {PermissionlessRouter} from "test/mock/PermissionlessRouter.sol";
import {Root} from "src/Root.sol";
import {LiquidityPool} from "src/LiquidityPool.sol";

import {AxelarScript} from "script/Axelar.s.sol";
import "script/Deployer.sol";
import "src/util/MathLib.sol";
import "forge-std/Test.sol";

interface ApproveLike {
    function approve(address, uint256) external;
}

contract DeployTest is Test, Deployer {
    using MathLib for uint128;

    uint8 constant PRICE_DECIMALS = 18;

    address self;
    ERC20 erc20;

    function setUp() public {
        deployInvestmentManager(address(this));
        PermissionlessRouter router = new PermissionlessRouter();
        wire(address(router));
        RouterLike(address(router)).file("gateway", address(gateway));

        giveAdminAccess();

        erc20 = newErc20("Test", "TEST", 6); // TODO: fuzz decimals
        self = address(this);
    }

    function testDeployAndInvestRedeem(
        uint64 poolId,
        string memory tokenName,
        string memory tokenSymbol,
        bytes16 trancheId
    ) public {
        uint8 decimals = 6; // TODO: use fuzzed decimals
        uint128 price = uint128(2 * 10 ** PRICE_DECIMALS); //TODO: fuzz price
        uint256 amount = 1000 * 10 ** erc20.decimals();
        uint64 validUntil = uint64(block.timestamp + 1000 days);
        address lPool_ = deployPoolAndTranche(poolId, trancheId, tokenName, tokenSymbol, decimals);
        LiquidityPool lPool = LiquidityPool(lPool_);

        deal(address(erc20), self, amount);

        vm.prank(address(gateway));
        poolManager.updateMember(poolId, trancheId, self, validUntil);

        depositMint(poolId, trancheId, price, amount, lPool);
        amount = lPool.balanceOf(self);

        redeemWithdraw(poolId, trancheId, price, amount, lPool);
    }

    function depositMint(uint64 poolId, bytes16 trancheId, uint128 price, uint256 amount, LiquidityPool lPool) public {
        erc20.approve(address(investmentManager), amount); // add allowance
        lPool.requestDeposit(amount, self);

        // ensure funds are locked in escrow
        assertEq(erc20.balanceOf(address(escrow)), amount);
        assertEq(erc20.balanceOf(self), 0);

        // trigger executed collectInvest
        uint128 _currencyId = poolManager.currencyAddressToId(address(erc20)); // retrieve currencyId

        uint128 trancheTokensPayout = _toUint128(
            uint128(amount).mulDiv(
                10 ** (PRICE_DECIMALS - erc20.decimals() + lPool.decimals()), price, MathLib.Rounding.Down
            )
        );

        // Assume an epoch execution happens on cent chain
        // Assume a bot calls collectInvest for this user on cent chain

        vm.prank(address(gateway));
        investmentManager.handleExecutedCollectInvest(
            poolId, trancheId, self, _currencyId, uint128(amount), trancheTokensPayout, 0
        );

        assertEq(lPool.maxMint(self), trancheTokensPayout);
        assertEq(lPool.maxDeposit(self), amount);
        assertEq(lPool.balanceOf(address(escrow)), trancheTokensPayout);
        assertEq(erc20.balanceOf(self), 0);

        uint256 div = 2;
        lPool.deposit(amount / div, self);

        assertEq(lPool.balanceOf(self), trancheTokensPayout / div);
        assertEq(lPool.balanceOf(address(escrow)), trancheTokensPayout - trancheTokensPayout / div);
        assertEq(lPool.maxMint(self), trancheTokensPayout - trancheTokensPayout / div);
        assertEq(lPool.maxDeposit(self), amount - amount / div); // max deposit

        lPool.mint(lPool.maxMint(self), self);

        assertEq(lPool.balanceOf(self), trancheTokensPayout);
        assertTrue(lPool.balanceOf(address(escrow)) <= 1);
        assertTrue(lPool.maxMint(self) <= 1);
    }

    function redeemWithdraw(uint64 poolId, bytes16 trancheId, uint128 price, uint256 amount, LiquidityPool lPool)
        public
    {
        vm.expectRevert(bytes("ERC20/insufficient-allowance"));
        lPool.requestRedeem(amount, self);
        lPool.approve(address(investmentManager), amount);
        lPool.requestRedeem(amount, self);

        // redeem
        uint128 _currencyId = poolManager.currencyAddressToId(address(erc20)); // retrieve currencyId
        uint128 currencyPayout = _toUint128(
            uint128(amount).mulDiv(price, 10 ** (18 - erc20.decimals() + lPool.decimals()), MathLib.Rounding.Down)
        );
        // Assume an epoch execution happens on cent chain
        // Assume a bot calls collectRedeem for this user on cent chain
        vm.prank(address(gateway));
        investmentManager.handleExecutedCollectRedeem(
            poolId, trancheId, self, _currencyId, currencyPayout, uint128(amount), 0
        );

        assertEq(lPool.maxWithdraw(self), currencyPayout);
        assertEq(lPool.maxRedeem(self), amount);
        assertEq(lPool.balanceOf(address(escrow)), 0);

        uint128 div = 2;
        lPool.redeem(amount / div, self, self);
        assertEq(lPool.balanceOf(self), 0);
        assertEq(lPool.balanceOf(address(escrow)), 0);
        assertEq(erc20.balanceOf(self), currencyPayout / div);
        assertEq(lPool.maxWithdraw(self), currencyPayout / div);
        assertEq(lPool.maxRedeem(self), amount / div);

        lPool.withdraw(lPool.maxWithdraw(self), self, self);
        assertEq(lPool.balanceOf(self), 0);
        assertEq(lPool.balanceOf(address(escrow)), 0);
        assertEq(erc20.balanceOf(self), currencyPayout);
        assertEq(lPool.maxWithdraw(self), 0);
        assertEq(lPool.maxRedeem(self), 0);
    }

    // helpers

    function deployPoolAndTranche(
        uint64 poolId,
        bytes16 trancheId,
        string memory tokenName,
        string memory tokenSymbol,
        uint8 decimals
    ) public returns (address) {
        vm.startPrank(address(gateway));
        poolManager.addPool(poolId);
        poolManager.addTranche(poolId, trancheId, tokenName, tokenSymbol, decimals);
        poolManager.addCurrency(1, address(erc20));
        poolManager.allowInvestmentCurrency(poolId, 1);
        vm.stopPrank();

        poolManager.deployTranche(poolId, trancheId);
        address lPool = poolManager.deployLiquidityPool(poolId, trancheId, address(erc20));
        return lPool;
    }

    function _toUint128(uint256 _value) internal pure returns (uint128 value) {
        if (_value > type(uint128).max) {
            revert();
        } else {
            value = uint128(_value);
        }
    }

    function newErc20(string memory name, string memory symbol, uint8 decimals) internal returns (ERC20) {
        ERC20 currency = new ERC20(decimals);
        currency.file("name", name);
        currency.file("symbol", symbol);
        return currency;
    }
}
