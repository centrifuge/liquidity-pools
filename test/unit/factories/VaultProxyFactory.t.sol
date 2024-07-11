// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.26;

import {VaultProxy, VaultProxyFactory} from "src/factories/VaultProxyFactory.sol";
import {ERC20} from "src/token/ERC20.sol";
import {MockVault} from "test/mocks/MockVault.sol";
import {MockCentrifugeRouter} from "test/mocks/MockCentrifugeRouter.sol";
import "forge-std/Test.sol";

contract VaultProxyFactoryTest is Test {
    MockCentrifugeRouter router;
    MockVault vault;
    VaultProxyFactory factory;
    ERC20 asset;
    ERC20 share;

    function setUp() public {
        router = new MockCentrifugeRouter();
        vault = new MockVault();
        factory = new VaultProxyFactory(address(router));
        asset = new ERC20(18);
        share = new ERC20(18);
    }

    function testVaultProxyCreation(address user) public {
        VaultProxy proxy = VaultProxy(factory.newVaultProxy(address(vault), user));
        assertEq(factory.router(), address(router));
        assertEq(factory.proxies(keccak256(abi.encodePacked(address(vault), user))), address(proxy));
        assertEq(address(proxy.router()), address(router));
        assertEq(proxy.vault(), address(vault));
        assertEq(proxy.user(), user);

        // Proxies cannot be deployed twice
        vm.expectRevert(bytes("VaultProxyFactory/proxy-already-deployed"));
        factory.newVaultProxy(address(vault), user);
    }

    function testVaultProxyDeposit(uint256 amount) public {
        address user = makeAddr("user");

        VaultProxy proxy = VaultProxy(factory.newVaultProxy(address(vault), user));
        asset.mint(user, amount);
        vm.deal(address(this), 1 ether);

        vm.expectRevert(bytes("VaultProxyFactory/zero-asset-allowance"));
        proxy.requestDeposit();

        assertEq(asset.balanceOf(user), amount);
        assertEq(asset.balanceOf(address(router)), 0);

        vm.prank(user);
        asset.approve(address(proxy), amount);
        
        proxy.requestDeposit{ value: 1 ether }();

        assertEq(asset.balanceOf(user), 0);
        assertEq(asset.balanceOf(address(router)), amount);

        assertEq(router.values_address("requestDeposit_vault"), address(vault));
        assertEq(router.values_uint256("requestDeposit_amount"), amount);
        assertEq(router.values_address("requestDeposit_controller"), user);
        assertEq(router.values_address("requestDeposit_owner"), address(router));
        assertEq(router.values_uint256("requestDeposit_topUpAmount"), 1 ether);
    }
}
