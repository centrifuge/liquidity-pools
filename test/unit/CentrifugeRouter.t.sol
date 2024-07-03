// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import "test/BaseTest.sol";
import "src/interfaces/IERC7575.sol";
import "src/interfaces/IERC7540.sol";
import "src/interfaces/IERC20.sol";
import {CastLib} from "src/libraries/CastLib.sol";

contract CentrifugeRouterTest is BaseTest {
    using CastLib for *;

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

    function testRequestDeposit() public {
        address vault_ = deploySimpleVault();
        vm.label(vault_, "vault");
        ERC7540Vault vault = ERC7540Vault(vault_);

        uint256 amount = 100 * 10 ** 18;
        assertEq(erc20.balanceOf(address(escrow)), 0);

        erc20.mint(self, amount);
        erc20.approve(address(vault_), amount);

        centrifugeChain.updateMember(vault.poolId(), vault.trancheId(), self, type(uint64).max);

        centrifugeRouter.requestDeposit(vault_, amount, self, self);

        assertEq(erc20.balanceOf(address(escrow)), amount);
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

    function testUnlockDepositRequest() public {
        address vault_ = deploySimpleVault();
        vm.label(vault_, "vault");

        uint256 amount = 100 * 10 ** 18;
        assertEq(erc20.balanceOf(address(routerEscrow)), 0);

        erc20.mint(self, amount);
        erc20.approve(address(centrifugeRouter), amount);

        centrifugeRouter.lockDepositRequest(vault_, amount, self, self);
        assertEq(erc20.balanceOf(address(routerEscrow)), amount);

        centrifugeRouter.unlockDepositRequest(vault_);
        assertEq(erc20.balanceOf(address(routerEscrow)), 0);
        assertEq(erc20.balanceOf(self), amount);
    }

    function testCancelDepositRequest() public {
        address vault_ = deploySimpleVault();
        vm.label(vault_, "vault");

        uint256 amount = 100 * 10 ** 18;
        assertEq(erc20.balanceOf(address(routerEscrow)), 0);

        erc20.mint(self, amount);
        erc20.approve(address(centrifugeRouter), amount);

        centrifugeRouter.lockDepositRequest(vault_, amount, self, self);
        assertEq(erc20.balanceOf(address(routerEscrow)), amount);
        assertEq(investmentManager.pendingCancelDepositRequest(vault_, self), false);

        centrifugeRouter.cancelDepositRequest(vault_, self);
        assertEq(investmentManager.pendingCancelDepositRequest(vault_, self), true);
        assertEq(erc20.balanceOf(address(routerEscrow)), amount);
    }

    function testClaimCancelDepositRequest() public {
        address vault_ = deploySimpleVault();
        vm.label(vault_, "vault");
        ERC7540Vault vault = ERC7540Vault(vault_);

        uint256 amount = 100 * 10 ** 18;

        erc20.mint(self, amount);
        erc20.approve(address(centrifugeRouter), amount);

        centrifugeRouter.lockDepositRequest(vault_, amount, self, self);
        centrifugeRouter.cancelDepositRequest(vault_, self);
        assertEq(investmentManager.pendingCancelDepositRequest(vault_, self), true);
        assertEq(erc20.balanceOf(address(routerEscrow)), amount);
        centrifugeChain.isFulfilledCancelDepositRequest(vault.poolId(), vault.trancheId(), self.toBytes32(), defaultAssetId, uint128(amount), uint128(amount));
        assertEq(investmentManager.claimableCancelDepositRequest(vault_, self), true);

        centrifugeRouter.claimCancelDepositRequest(vault_, self, self);
        assertEq(erc20.balanceOf(address(routerEscrow)), 0);
        assertEq(erc20.balanceOf(self), amount);
    }

    function testRequestRedeem() external {
        // Deposit first
        address vault_ = deploySimpleVault();
        vm.label(vault_, "vault");
        ERC7540Vault vault = ERC7540Vault(vault_);
        uint256 amount = 100 * 10 ** 18;
        erc20.mint(self, amount);
        erc20.approve(address(vault_), amount);
        centrifugeChain.updateMember(vault.poolId(), vault.trancheId(), self, type(uint64).max);
        centrifugeRouter.requestDeposit(vault_, amount, self, self);
        IERC20 share = IERC20(address(vault.share()));
        centrifugeChain.isFulfilledDepositRequest(
            vault.poolId(),
            vault.trancheId(),
            bytes32(bytes20(self)),
            defaultAssetId,
            uint128(amount),
            uint128(amount),
            uint128(amount)
        );
        vault.deposit(amount, self, self);
        assertEq(share.balanceOf(address(self)), amount);

        // Then redeem
        share.approve(vault_, amount);
        share.approve(address(centrifugeRouter), amount);
        centrifugeRouter.requestRedeem(vault_, amount, self, self);
        assertEq(share.balanceOf(address(self)), 0);
    }

    function testCancelRedeemRequest() public {
        // Deposit first
        address vault_ = deploySimpleVault();
        vm.label(vault_, "vault");
        ERC7540Vault vault = ERC7540Vault(vault_);
        uint256 amount = 100 * 10 ** 18;
        erc20.mint(self, amount);
        erc20.approve(address(vault_), amount);
        centrifugeChain.updateMember(vault.poolId(), vault.trancheId(), self, type(uint64).max);
        centrifugeRouter.requestDeposit(vault_, amount, self, self);
        IERC20 share = IERC20(address(vault.share()));
        centrifugeChain.isFulfilledDepositRequest(
            vault.poolId(),
            vault.trancheId(),
            bytes32(bytes20(self)),
            defaultAssetId,
            uint128(amount),
            uint128(amount),
            uint128(amount)
        );
        vault.deposit(amount, self, self);
        assertEq(share.balanceOf(address(self)), amount);

        // Then redeem
        share.approve(vault_, amount);
        share.approve(address(centrifugeRouter), amount);
        centrifugeRouter.requestRedeem(vault_, amount, self, self);
        assertEq(share.balanceOf(address(self)), 0);

        centrifugeRouter.cancelRedeemRequest(vault_, self);
        assertEq(investmentManager.pendingCancelRedeemRequest(vault_, self), true);
    }

    function testClaimCancelRedeemRequest() public {
        // Deposit first
        address vault_ = deploySimpleVault();
        vm.label(vault_, "vault");
        ERC7540Vault vault = ERC7540Vault(vault_);
        uint256 amount = 100 * 10 ** 18;
        erc20.mint(self, amount);
        erc20.approve(address(vault_), amount);
        centrifugeChain.updateMember(vault.poolId(), vault.trancheId(), self, type(uint64).max);
        centrifugeRouter.requestDeposit(vault_, amount, self, self);
        IERC20 share = IERC20(address(vault.share()));
        centrifugeChain.isFulfilledDepositRequest(
            vault.poolId(),
            vault.trancheId(),
            bytes32(bytes20(self)),
            defaultAssetId,
            uint128(amount),
            uint128(amount),
            uint128(amount)
        );
        vault.deposit(amount, self, self);
        assertEq(share.balanceOf(address(self)), amount);

        // Then redeem
        share.approve(vault_, amount);
        share.approve(address(centrifugeRouter), amount);
        centrifugeRouter.requestRedeem(vault_, amount, self, self);
        assertEq(share.balanceOf(address(self)), 0);

        centrifugeRouter.cancelRedeemRequest(vault_, self);
        assertEq(investmentManager.pendingCancelRedeemRequest(vault_, self), true);

        centrifugeChain.isFulfilledCancelRedeemRequest(vault.poolId(), vault.trancheId(), self.toBytes32(), defaultAssetId, uint128(amount), uint128(amount));
        centrifugeRouter.claimCancelRedeemRequest(vault_, self, self);
        assertEq(share.balanceOf(address(self)), amount);
    }

}