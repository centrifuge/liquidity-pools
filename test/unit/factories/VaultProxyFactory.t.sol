// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.26;

import {VaultProxy, VaultProxyFactory} from "src/factories/VaultProxyFactory.sol";
import {ERC20} from "src/token/ERC20.sol";
import {IERC7540Vault} from "src/interfaces/IERC7540.sol";
import "test/BaseTest.sol";

contract VaultProxyFactoryTest is BaseTest {
    IERC7540Vault vault;
    ERC20 asset = new ERC20(18);
    ERC20 share = new ERC20(18);

    function testVaultProxyCreation(address user) public {
        vault = IERC7540Vault(deployVault(1, 18, restrictionManager, "", "", "1", 1, address(asset)));

        VaultProxy proxy = VaultProxy(VaultProxyFactory(vaultProxyFactory).newVaultProxy(address(vault), user));
        assertEq(VaultProxyFactory(vaultProxyFactory).router(), address(router));
        assertEq(
            VaultProxyFactory(vaultProxyFactory).proxies(keccak256(abi.encodePacked(address(vault), user))),
            address(proxy)
        );
        assertEq(address(proxy.router()), address(router));
        assertEq(proxy.vault(), address(vault));
        assertEq(proxy.user(), user);

        // Proxies cannot be deployed twice
        vm.expectRevert(bytes("VaultProxyFactory/proxy-already-deployed"));
        VaultProxyFactory(vaultProxyFactory).newVaultProxy(address(vault), user);
    }

    function testVaultProxyDeposit(uint256 amount) public {
        amount = bound(amount, 1, type(uint128).max);

        vault = IERC7540Vault(deployVault(1, 18, restrictionManager, "", "", "1", 1, address(asset)));
        address user = makeAddr("user");

        VaultProxy proxy = VaultProxy(VaultProxyFactory(vaultProxyFactory).newVaultProxy(address(vault), user));
        centrifugeChain.updateMember(vault.poolId(), vault.trancheId(), user, type(uint64).max);

        asset.mint(user, amount);
        vm.deal(address(this), 1 ether);

        vm.expectRevert(bytes("VaultProxy/zero-asset-allowance"));
        proxy.requestDeposit();

        assertEq(asset.balanceOf(user), amount);
        assertEq(asset.balanceOf(address(escrow)), 0);

        vm.prank(user);
        asset.approve(address(proxy), amount);

        proxy.requestDeposit{value: 1 ether}();

        assertEq(asset.balanceOf(user), 0);
        assertEq(asset.balanceOf(address(escrow)), amount);

        centrifugeChain.isFulfilledDepositRequest(
            vault.poolId(), vault.trancheId(), bytes32(bytes20(user)), 1, uint128(amount), uint128(amount)
        );

        proxy.claimDeposit();
        assertEq(share.balanceOf(user), amount);
    }

    function testVaultProxyRedeem(uint256 amount) public {
        amount = bound(amount, 1, type(uint128).max);

        vault = IERC7540Vault(deployVault(1, 18, restrictionManager, "", "", "1", 1, address(asset)));
        address user = makeAddr("user");

        VaultProxy proxy = VaultProxy(VaultProxyFactory(vaultProxyFactory).newVaultProxy(address(vault), user));
        centrifugeChain.updateMember(vault.poolId(), vault.trancheId(), address(proxy), type(uint64).max);

        share.mint(user, amount);
        vm.deal(address(this), 1 ether);

        vm.expectRevert(bytes("VaultProxy/zero-share-allowance"));
        proxy.requestRedeem();

        assertEq(share.balanceOf(user), amount);
        assertEq(share.balanceOf(address(router)), 0);

        vm.prank(user);
        share.approve(address(proxy), amount);

        proxy.requestRedeem{value: 1 ether}();

        assertEq(share.balanceOf(user), 0);
        assertEq(share.balanceOf(address(router)), amount);

        // assertEq(router.values_address("requestRedeem_vault"), address(vault));
        // assertEq(router.values_uint256("requestRedeem_amount"), amount);
        // assertEq(router.values_address("requestRedeem_controller"), user);
        // assertEq(router.values_address("requestRedeem_owner"), address(router));
        // assertEq(router.values_uint256("requestRedeem_topUpAmount"), 1 ether);
    }
}
