// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import "../rpc/RPC.t.sol";
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

    function testCastSuccessfull() public {
        address depricatedLP = spell.DEPRICATED_LIQUIDITY_POOL();
        LiquidityPoolLike lp = LiquidityPoolLike(depricatedLP);
        address liquidityPoolToRemove =
            PoolManagerLike(poolManager).getLiquidityPool(lp.poolId(), lp.trancheId(), lp.asset());
        assertEq(liquidityPoolToRemove, address(0));

        // check if pool removed correctly
        assertEq(InvestmentManager(investmentManager).wards(depricatedLP), 0);
        assertEq(TrancheToken(anemoyToken).wards(depricatedLP), 0);
        assertEq(TrancheToken(anemoyToken).isTrustedForwarder(depricatedLP), false);
        assertEq(TrancheToken(anemoyToken).allowance(address(escrow), depricatedLP), 0);
    }
}
