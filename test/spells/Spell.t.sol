// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import "../fork/Fork.t.sol";
import "./Spell.sol";

contract SpellTest is RPCTest {
    Spell spell;

    function setUp() public override {
        super.setUp();
        spell = new Spell();

        address newLPFactory = spell.LIQUIDITY_POOL_FACTORY_NEW();

        // rely root on new factory -> to be done manually before spell cast
        vm.prank(deployer);
        AuthLike(newLPFactory).rely(root);

        liquidityPoolFactory = newLPFactory; // replace liquidityPoolFactory address in the deployment addresses to
        // check for correct wiring
        castSpell();
    }

    function castSpell() public {
        // admin submits a tx to delayedAdmin in order to rely spell -> to be done manually before spell cast
        vm.prank(admin);
        DelayedAdmin(delayedAdmin).scheduleRely(address(spell));
        // warp to the time when the spell can be cast -> current block + delay
        vm.warp(block.timestamp + Root(root).delay());
        Root(root).executeScheduledRely(address(spell)); // --> to be called after delay has passed
        spell.cast();
    }

    function testCastSuccessful() public {
        address newLP_ = spell.newLiquidityPool();
        address deprecatedLP_ = spell.DEPRECATED_LIQUIDITY_POOL();
        LiquidityPoolLike deprecatedLP = LiquidityPoolLike(deprecatedLP_);
        LiquidityPoolLike newLP = LiquidityPoolLike(newLP_);

        assertEq(deprecatedLP.poolId(), newLP.poolId());
        assertEq(deprecatedLP.trancheId(), newLP.trancheId());
        assertEq(deprecatedLP.asset(), newLP.asset());

        // check if deprectaed pool removed correctly
        assertEq(InvestmentManager(investmentManager).wards(deprecatedLP_), 0);
        assertEq(TrancheToken(anemoyToken).wards(deprecatedLP_), 0);
        assertEq(TrancheToken(anemoyToken).isTrustedForwarder(deprecatedLP_), false);
        assertEq(TrancheToken(anemoyToken).allowance(address(escrow), deprecatedLP_), 0);

        // check if new pool added correctly
        assertEq(InvestmentManager(investmentManager).wards(newLP_), 1);
        assertEq(TrancheToken(anemoyToken).wards(newLP_), 1);
        assertEq(TrancheToken(anemoyToken).isTrustedForwarder(newLP_), true);
        assertEq(TrancheToken(anemoyToken).allowance(address(escrow), newLP_), UINT256_MAX);
    }
}
