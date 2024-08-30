// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.26;

import "test/BaseTest.sol";
import {CastLib} from "src/libraries/CastLib.sol";
import {LockupManager} from "src/token/LockupManager.sol";

contract LockupManagerTest is BaseTest {
    using CastLib for *;

    function testLockupManager(uint256 amount) public {
        amount = bound(amount, 0, type(uint128).max);

        LockupManager hook = new LockupManager(address(root), address(escrow), address(this));
        hook.rely(address(poolManager));
        hook.rely(address(root));

        address vault_ = deployVaultCustomHook(address(hook));
        ERC7540Vault vault = ERC7540Vault(vault_);
        ITranche tranche = ITranche(address(vault.share()));
        vm.warp(block.timestamp + 1 days);
        hook.setLockupPeriod(address(tranche), 3);

        address investor1 = makeAddr("investor1");
        address investor2 = makeAddr("investor2");
        root.relyContract(address(tranche), self);
        centrifugeChain.updateMember(vault.poolId(), vault.trancheId(), investor1, type(uint64).max);
        centrifugeChain.updateMember(vault.poolId(), vault.trancheId(), investor2, type(uint64).max);
        tranche.mint(investor1, amount);

        // After 2 days, the balance is locked, but transfers can happen
        vm.warp(block.timestamp + 2 days);
        assertEq(hook.unlocked(address(tranche), investor1), 0);

        vm.prank(investor1);
        tranche.transfer(investor2, amount / 2);

        assertEq(hook.unlocked(address(tranche), investor1), 0);
        assertEq(hook.unlocked(address(tranche), investor2), 0);

        vm.expectRevert(bytes(""));
        vm.prank(investor1);
        vault.requestRedeem(amount / 2, investor1, investor1);

        // After 4 days, investor1's balance is unlocked, investor2's balance not yet
        vm.warp(block.timestamp + 2 days);
        assertEq(hook.unlocked(address(tranche), investor1), amount / 2);
        assertEq(hook.unlocked(address(tranche), investor2), 0);

        vm.prank(investor1);
        vault.requestRedeem(amount / 2, investor1, investor1);

        vm.expectRevert(bytes(""));
        vm.prank(investor2);
    }
}
