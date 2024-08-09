// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.26;

import "test/BaseTest.sol";
import {CastLib} from "src/libraries/CastLib.sol";
import {FreezeManager} from "src/token/FreezeManager.sol";

contract FreezeManagerTest is BaseTest {
    using CastLib for *;

    function testFreezeManager(uint256 amount) public {
        // If lower than 4 or odd, rounding down can lead to not receiving any tokens
        amount = uint128(bound(amount, 4, MAX_UINT128));
        vm.assume(amount % 2 == 0);

        uint128 price = 2 * 10 ** 18;

        FreezeManager hook = new FreezeManager(address(root), address(this));
        hook.rely(address(poolManager));
        hook.rely(address(root));

        address vault_ = deployVaultCustomHook(address(hook));
        ERC7540Vault vault = ERC7540Vault(vault_);
        ITranche tranche = ITranche(address(vault.share()));
        centrifugeChain.updateTranchePrice(
            vault.poolId(), vault.trancheId(), defaultAssetId, price, uint64(block.timestamp)
        );

        erc20.mint(self, amount);

        centrifugeChain.allowAsset(vault.poolId(), defaultAssetId);
        erc20.approve(vault_, amount);
        vault.requestDeposit(amount, self, self);

        assertEq(erc20.balanceOf(address(escrow)), amount);
        assertEq(erc20.balanceOf(self), 0);
        assertEq(vault.pendingDepositRequest(0, self), amount);
        assertEq(vault.claimableDepositRequest(0, self), 0);

        centrifugeChain.isFulfilledDepositRequest(
            vault.poolId(), vault.trancheId(), bytes32(bytes20(self)), poolManager.assetToId(address(erc20)), uint128(amount), uint128(amount)
        );

        assertEq(vault.maxMint(self), amount);
        vault.mint(amount, self, self);
        assertEq(tranche.balanceOf(self), amount);
    }
}
