// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.26;

import "test/BaseTest.sol";
import "src/interfaces/IERC7575.sol";
import "src/interfaces/IERC7540.sol";
import {MockERC20Wrapper} from "test/mocks/MockERC20Wrapper.sol";

contract ERC20WrapperFake {
    address public underlying;

    constructor(address underlying_) {
        underlying = underlying_;
    }
}

contract CentrifugeRouterTest is BaseTest {
    function testInitialization() public {
        assertEq(address(router.escrow()), address(routerEscrow));
        assertEq(address(router.gateway()), address(gateway));
        assertEq(address(router.poolManager()), address(poolManager));
    }

    function testGetVault() public {
        address vault_ = deploySimpleVault();
        ERC7540Vault vault = ERC7540Vault(vault_);
        vm.label(vault_, "vault");

        assertEq(router.getVault(vault.poolId(), vault.trancheId(), address(erc20)), vault_);
    }

    function testRecoverTokens() public {
        uint256 amount = 100;
        erc20.mint(address(router), amount);
        vm.prank(address(root));
        router.recoverTokens(address(erc20), address(this), amount);
        assertEq(erc20.balanceOf(address(this)), amount);
    }

    function testLockDepositRequests() public {
        address vault_ = deploySimpleVault();
        vm.label(vault_, "vault");

        uint256 amount = 100 * 10 ** 18;
        assertEq(erc20.balanceOf(address(routerEscrow)), 0);

        erc20.mint(self, amount);
        erc20.approve(address(router), amount);

        vm.expectRevert("PoolManager/unknown-vault");
        router.lockDepositRequest(makeAddr("maliciousVault"), amount, self, self);

        router.lockDepositRequest(vault_, amount, self, self);

        assertEq(erc20.balanceOf(address(routerEscrow)), amount);
    }

    function testUnlockDepositRequests() public {
        address vault_ = deploySimpleVault();
        vm.label(vault_, "vault");

        uint256 amount = 100 * 10 ** 18;

        erc20.mint(self, amount);
        erc20.approve(address(router), amount);

        vm.expectRevert(bytes("CentrifugeRouter/user-has-no-locked-balance"));
        router.unlockDepositRequest(vault_, self);

        router.lockDepositRequest(vault_, amount, self, self);
        assertEq(erc20.balanceOf(address(routerEscrow)), amount);
        assertEq(erc20.balanceOf(self), 0);
        router.unlockDepositRequest(vault_, self);
        assertEq(erc20.balanceOf(address(routerEscrow)), 0);
        assertEq(erc20.balanceOf(self), amount);
    }

    function testOpenAndClose() public {
        address vault_ = deploySimpleVault();
        vm.label(vault_, "vault");

        assertFalse(router.opened(self, vault_));
        router.open(vault_);
        assertTrue(router.opened(self, vault_));
        router.close(vault_);
        assertFalse(router.opened(self, vault_));
    }

    function testWrap() public {
        uint256 amount = 150 * 10 ** 18;
        uint256 balance = 100 * 10 ** 18;
        address receiver = makeAddr("receiver");
        MockERC20Wrapper wrapper = new MockERC20Wrapper(address(erc20));

        vm.expectRevert(bytes("CentrifugeRouter/invalid-owner"));
        router.wrap(address(wrapper), amount, receiver, makeAddr("ownerIsNeitherCallerNorRouter"));

        vm.expectRevert(bytes("CentrifugeRouter/zero-balance"));
        router.wrap(address(wrapper), amount, receiver, self);

        erc20.mint(self, balance);
        erc20.approve(address(router), amount);
        wrapper.shouldFail("deposit", true);
        vm.expectRevert(bytes("CentrifugeRouter/deposit-for-failed"));
        router.wrap(address(wrapper), amount, receiver, self);

        wrapper.shouldFail("deposit", false);
        router.wrap(address(wrapper), amount, receiver, self);
        assertEq(wrapper.balanceOf(receiver), balance);
        assertEq(erc20.balanceOf(self), 0);

        erc20.mint(address(router), balance);
        router.wrap(address(wrapper), amount, receiver, address(router));
        assertEq(wrapper.balanceOf(receiver), 200 * 10 ** 18);
        assertEq(erc20.balanceOf(address(router)), 0);
    }

    function testUnwrap() public {
        uint256 amount = 150 * 10 ** 18;
        uint256 balance = 100 * 10 ** 18;
        MockERC20Wrapper wrapper = new MockERC20Wrapper(address(erc20));
        erc20.mint(self, balance);
        erc20.approve(address(router), amount);

        vm.expectRevert(bytes("CentrifugeRouter/zero-balance"));
        router.unwrap(address(wrapper), amount, self);

        router.wrap(address(wrapper), amount, address(router), self);
        wrapper.shouldFail("withdraw", true);
        vm.expectRevert(bytes("CentrifugeRouter/withdraw-to-failed"));
        router.unwrap(address(wrapper), amount, self);
        wrapper.shouldFail("withdraw", false);

        assertEq(wrapper.balanceOf(address(router)), balance);
        assertEq(erc20.balanceOf(self), 0);
        router.unwrap(address(wrapper), amount, self);
        assertEq(wrapper.balanceOf(address(router)), 0);
        assertEq(erc20.balanceOf(self), balance);
    }

    function testEstimate() public {
        bytes memory message = "IRRELEVANT";
        uint256 estimated = router.estimate(message);
        (, uint256 gatewayEstimated) = gateway.estimate(message);
        assertEq(estimated, gatewayEstimated);
    }
}
