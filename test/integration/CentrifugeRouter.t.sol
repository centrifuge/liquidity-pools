// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import "test/BaseTest.sol";
import "src/interfaces/IERC7575.sol";
import "src/interfaces/IERC7540.sol";
import {SucceedingRequestReceiver} from "test/mocks/SucceedingRequestReceiver.sol";
import {FailingRequestReceiver} from "test/mocks/FailingRequestReceiver.sol";

contract CentrifugeRouterTest is BaseTest {

    function testCFGRouterDeposit(uint256 amount) public {
        // If lower than 4 or odd, rounding down can lead to not receiving any tokens
        amount = uint128(bound(amount, 4, MAX_UINT128));
        vm.assume(amount % 2 == 0);

        address vault_ = deploySimpleVault();
        ERC7540Vault vault = ERC7540Vault(vault_);
        vm.label(vault_, "vault");

        erc20.mint(self, amount);

        vm.expectRevert(bytes("SafeTransferLib/safe-transfer-from-failed")); // fail: no allowance
        cfgRouter.requestDeposit(vault_, amount);

        erc20.approve(address(cfgRouter), amount); // grant approval to cfg router

        vm.expectRevert(bytes("InvestmentManager/transfer-not-allowed")); // fail: receiver not member
        cfgRouter.requestDeposit(vault_, amount);

        centrifugeChain.updateMember(vault.poolId(), vault.trancheId(), self, type(uint64).max); // add user as member
        cfgRouter.requestDeposit(vault_, amount);

        // trigger - deposit order fulfillment
        (uint128 trancheTokensPayout) = fulfillDepositRequest(vault, amount);

        assertEq(vault.maxMint(self), trancheTokensPayout); // max deposit
        assertEq(vault.maxDeposit(self), amount); // max deposit
        TrancheTokenLike trancheToken = TrancheTokenLike(address(vault.share()));
        assertEq(trancheToken.balanceOf(address(escrow)), trancheTokensPayout); // assert tranche tokens minted

        // vm.expectRevert(bytes("LiquidityPool/not-owner-or-endorsed"));
        cfgRouter.claimDeposit(vault_, self); // claim Deposit
        assertApproxEqAbs(trancheToken.balanceOf(self), trancheTokensPayout, 1);
        assertApproxEqAbs(trancheToken.balanceOf(self), trancheTokensPayout, 1);
        assertApproxEqAbs(trancheToken.balanceOf(address(escrow)), 0, 1);
        assertApproxEqAbs(erc20.balanceOf(address(escrow)), amount, 1);
    }

    function testCFGRouterAsyncDeposit(uint256 amount) public {
        amount = uint128(bound(amount, 4, MAX_UINT128));
        vm.assume(amount % 2 == 0);

        address vault_ = deploySimpleVault();
        ERC7540Vault vault = ERC7540Vault(vault_);
        vm.label(vault_, "vault");

        erc20.mint(self, amount);
        erc20.approve(address(cfgRouter), amount);
        centrifugeChain.updateMember(vault.poolId(), vault.trancheId(), self, type(uint64).max);
        cfgRouter.lockDepositRequest(vault_, amount);

        // Warp to simulate real-world async behavior
        vm.warp(10 days);

        // Any address should be able to call executeLockedDepositRequest for an investor
        address randomUser = address(0x123);
        vm.label(randomUser, "randomUser");
        vm.prank(randomUser);
        cfgRouter.executeLockedDepositRequest(vault_, address(this));

        (uint128 trancheTokensPayout) = fulfillDepositRequest(vault, amount);

        assertEq(vault.maxMint(self), trancheTokensPayout);
        assertEq(vault.maxDeposit(self), amount);
        TrancheTokenLike trancheToken = TrancheTokenLike(address(vault.share()));
        assertEq(trancheToken.balanceOf(address(escrow)), trancheTokensPayout);

        // Any address should be able to call claimDeposit for an investor
        vm.prank(randomUser);
        cfgRouter.claimDeposit(vault_, self);
        assertApproxEqAbs(trancheToken.balanceOf(self), trancheTokensPayout, 1);
        assertApproxEqAbs(trancheToken.balanceOf(self), trancheTokensPayout, 1);
        assertApproxEqAbs(trancheToken.balanceOf(address(escrow)), 0, 1);
        assertApproxEqAbs(erc20.balanceOf(address(escrow)), amount, 1);
    }

    function testCFGRouterRedeem(uint256 amount) public {
        // deposit
        amount = uint128(bound(amount, 4, MAX_UINT128));
        vm.assume(amount % 2 == 0);
        address vault_ = deploySimpleVault();
        ERC7540Vault vault = ERC7540Vault(vault_);
        vm.label(vault_, "vault");
        erc20.mint(self, amount);
        erc20.approve(address(cfgRouter), amount);
        centrifugeChain.updateMember(vault.poolId(), vault.trancheId(), self, type(uint64).max); // add user as member
        cfgRouter.requestDeposit(vault_, amount);
        (uint128 trancheTokensPayout) = fulfillDepositRequest(vault, amount);
        TrancheTokenLike trancheToken = TrancheTokenLike(address(vault.share()));
        cfgRouter.claimDeposit(vault_, self);

        // redeem
        trancheToken.approve(address(cfgRouter), trancheTokensPayout);
        cfgRouter.requestRedeem(vault_, trancheTokensPayout);
        (uint128 assetPayout) = fulfillRedeemRequest(vault, trancheTokensPayout);
        assertApproxEqAbs(trancheToken.balanceOf(self), 0, 1);
        assertApproxEqAbs(trancheToken.balanceOf(address(escrow)), 0, 1);
        assertApproxEqAbs(erc20.balanceOf(address(escrow)), amount, 1);
        assertApproxEqAbs(erc20.balanceOf(self), 0, 1);
    }

    function testCFGRouterRoundTrip() public {}

    function testCFGRouterDepositIntoMultipleVaults() public {}

    function testCFGRouterRedeemFromMultipleVaults() public {}

    function testMulticallingDepositClaimAndRedeem() public {}

    // --- helpers ---
    function fulfillDepositRequest(ERC7540Vault vault, uint256 amount) public returns (uint128 trancheTokensPayout){
        uint128 price = 2 * 10 ** 18;
        uint128 _currencyId = poolManager.assetToId(address(erc20)); // retrieve currencyId
        trancheTokensPayout = uint128(amount * 10 ** 18 / price); // trancheTokenPrice = 2$
        assertApproxEqAbs(trancheTokensPayout, amount / 2, 2);
        centrifugeChain.isFulfilledDepositRequest(
            vault.poolId(),
            vault.trancheId(),
            bytes32(bytes20(self)),
            _currencyId,
            uint128(amount),
            trancheTokensPayout,
            uint128(amount)
        );
    }

    function fulfillRedeemRequest(ERC7540Vault vault, uint256 amount) public returns (uint128 assetPayout){
        uint128 price = 2 * 10 ** 18;
        uint128 _currencyId = poolManager.assetToId(address(erc20)); // retrieve currencyId
        assetPayout = uint128(amount * price / 10 ** 18); // trancheTokenPrice = 2$
        assertApproxEqAbs(assetPayout, amount * 2, 2);
        centrifugeChain.isFulfilledRedeemRequest(
            vault.poolId(),
            vault.trancheId(),
            bytes32(bytes20(self)),
            _currencyId,
            assetPayout,
            uint128(amount)
        );
    }

}
