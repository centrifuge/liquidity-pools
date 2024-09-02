// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.26;

import "test/BaseTest.sol";
import {CastLib} from "src/libraries/CastLib.sol";
import {LockupManager} from "src/token/LockupManager.sol";

contract LockupManagerTest is BaseTest {
    using CastLib for *;

    uint256 constant ETHEREUM_GAS_LIMIT = 30_000_000;

    function testLockups(uint256 amount) public {
        amount = bound(amount, 2, type(uint128).max);

        LockupManager hook = new LockupManager(address(root), address(escrow), address(this));
        hook.rely(address(poolManager));
        hook.rely(address(root));

        address vault_ = deployVaultCustomHook(address(hook));
        ERC7540Vault vault = ERC7540Vault(vault_);
        ITranche tranche = ITranche(address(vault.share()));
        vm.warp(block.timestamp + 1 days);
        hook.setLockupPeriod(address(tranche), 3, 0);

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

        vm.prank(investor1);
        vm.expectRevert(bytes("ERC20/insufficient-allowance"));
        vault.requestRedeem(amount / 2, investor1, investor1);

        // After 4 days, investor1's balance is unlocked, investor2's balance not yet
        vm.warp(block.timestamp + 2 days);
        assertApproxEqAbs(hook.unlocked(address(tranche), investor1), amount / 2, 1);
        assertApproxEqAbs(hook.unlocked(address(tranche), investor2), 0, 1);

        vm.prank(investor1);
        vault.requestRedeem(amount / 2, investor1, investor1);

        vm.prank(investor2);
        vm.expectRevert(bytes("ERC20/insufficient-allowance"));
        vault.requestRedeem(amount / 2, investor2, investor2);
    }

    function testIfNoLockupIsSet(uint256 amount) public {
        amount = bound(amount, 2, type(uint128).max);

        LockupManager hook = new LockupManager(address(root), address(escrow), address(this));
        hook.rely(address(poolManager));
        hook.rely(address(root));

        address vault_ = deployVaultCustomHook(address(hook));
        ERC7540Vault vault = ERC7540Vault(vault_);
        ITranche tranche = ITranche(address(vault.share()));
        vm.warp(block.timestamp + 1 days);

        address investor1 = makeAddr("investor1");
        address investor2 = makeAddr("investor2");
        root.relyContract(address(tranche), self);
        centrifugeChain.updateMember(vault.poolId(), vault.trancheId(), investor1, type(uint64).max);
        centrifugeChain.updateMember(vault.poolId(), vault.trancheId(), investor2, type(uint64).max);
        tranche.mint(investor1, amount);

        vm.warp(block.timestamp + 2 days);
        assertEq(hook.unlocked(address(tranche), investor1), amount);

        vm.prank(investor1);
        tranche.transfer(investor2, amount / 2);

        assertApproxEqAbs(hook.unlocked(address(tranche), investor1), amount / 2, 1);
        assertApproxEqAbs(hook.unlocked(address(tranche), investor2), amount / 2, 1);

        vm.prank(investor1);
        vault.requestRedeem(amount / 2, investor1, investor1);
    }

    // We can do >10 years of transfers (each transfer grouped by day) without exceeding the
    // Ethereum gas limit with a transfer that loops over all unlocked transfers.
    function testLockupsWithManyTransfers(uint256 amount, uint8 lockupDays, uint256 numTransferDays) public {
        numTransferDays = bound(numTransferDays, 5, 365 * 10);
        lockupDays = uint8(bound(lockupDays, 5, numTransferDays));
        amount = bound(amount, 2, type(uint128).max / numTransferDays);

        LockupManager hook = new LockupManager(address(root), address(escrow), address(this));
        hook.rely(address(poolManager));
        hook.rely(address(root));

        address vault_ = deployVaultCustomHook(address(hook));
        ERC7540Vault vault = ERC7540Vault(vault_);
        ITranche tranche = ITranche(address(vault.share()));
        vm.warp(block.timestamp + 1 days);
        hook.setLockupPeriod(address(tranche), lockupDays, 0);

        address investor1 = makeAddr("investor1");
        address investor2 = makeAddr("investor2");
        root.relyContract(address(tranche), self);
        centrifugeChain.updateMember(vault.poolId(), vault.trancheId(), investor1, type(uint64).max);
        centrifugeChain.updateMember(vault.poolId(), vault.trancheId(), investor2, type(uint64).max);
        tranche.mint(investor1, amount * numTransferDays);

        for (uint256 i = 0; i < numTransferDays; i++) {
            // Unlocked balance should increase past the lockup period (as a griefing attack prevention)
            if (i < lockupDays - 1) {
                assertEq(hook.unlocked(address(tranche), investor2), 0);
            } else {
                assertApproxEqAbs(hook.unlocked(address(tranche), investor2), (i + 2 - lockupDays) * amount, 1);
            }

            vm.warp(block.timestamp + 1 days);
            vm.prank(investor1);
            tranche.transfer(investor2, amount);
        }

        uint256 gasStart = gasleft();
        vm.prank(investor2);
        tranche.transfer(investor1, amount * numTransferDays);
        uint256 gasUsed = gasStart - gasleft();
        assertTrue(gasUsed <= ETHEREUM_GAS_LIMIT);
    }
}
