// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.26;

import "test/BaseTest.sol";
import {CastLib} from "src/libraries/CastLib.sol";
import {LockupManager} from "src/token/LockupManager.sol";

contract LockupManagerTest is BaseTest {
    using CastLib for *;

    function testLockupManager(uint256 amount) public {
        LockupManager hook = new LockupManager(address(root), address(escrow), address(this));
        hook.rely(address(poolManager));
        hook.rely(address(root));

        address vault_ = deployVaultCustomHook(address(hook));
        ERC7540Vault vault = ERC7540Vault(vault_);
        ITranche tranche = ITranche(address(vault.share()));
        vm.warp(block.timestamp + 1 days);
        hook.setLockupPeriod(address(tranche), 3);

        address investor = makeAddr("investor");
        root.relyContract(address(tranche), self);
        centrifugeChain.updateMember(vault.poolId(), vault.trancheId(), investor, type(uint64).max);
        tranche.mint(investor, amount);

        assertEq(tranche.balanceOf(investor), amount);
        assertEq(hook.unlocked(address(tranche), investor), 0);

        vm.warp(block.timestamp + 5 days); // more than 3 days since it's rounded up to UTC midnight
        assertEq(hook.unlocked(address(tranche), investor), amount);
    }
}
