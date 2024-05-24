// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import "test/BaseTest.sol";
import "src/interfaces/IERC7575.sol";
import "src/interfaces/IERC7540.sol";
<<<<<<< HEAD
import {SucceedingRequestReceiver} from "test/mocks/SucceedingRequestReceiver.sol";
import {FailingRequestReceiver} from "test/mocks/FailingRequestReceiver.sol";
import {MockMulticall, Call} from "test/mocks/MockMulticall.sol";
=======
>>>>>>> liquidity-pool-router

contract CentrifugeRouterTest is BaseTest {
    function testCFGRouterDeposit(uint256 amount) public {
        // If lower than 4 or odd, rounding down can lead to not receiving any tokens
        amount = uint128(bound(amount, 4, MAX_UINT128));
        vm.assume(amount % 2 == 0);

        address vault_ = deploySimpleVault();
        ERC7540Vault vault = ERC7540Vault(vault_);
<<<<<<< HEAD
        vm.label(vault_, "vault");
=======
>>>>>>> liquidity-pool-router

        erc20.mint(self, amount);

        vm.expectRevert(bytes("SafeTransferLib/safe-transfer-from-failed")); // fail: no allowance
        cfgRouter.requestDeposit(vault_, amount);

        erc20.approve(address(cfgRouter), amount); // grant approval to cfg router

        vm.expectRevert(bytes("InvestmentManager/transfer-not-allowed")); // fail: receiver not member
        cfgRouter.requestDeposit(vault_, amount);

        centrifugeChain.updateMember(vault.poolId(), vault.trancheId(), self, type(uint64).max); // add user as member
        cfgRouter.requestDeposit(vault_, amount);

        // trigger - deposit order fulfillment
        uint128 assetId = poolManager.assetToId(address(erc20));
        (uint128 trancheTokensPayout) = fulfillDepositRequest(vault, assetId, amount);

        assertEq(vault.maxMint(self), trancheTokensPayout); // max deposit
        assertEq(vault.maxDeposit(self), amount); // max deposit
        TrancheTokenLike trancheToken = TrancheTokenLike(address(vault.share()));
        assertEq(trancheToken.balanceOf(address(escrow)), trancheTokensPayout); // assert tranche tokens minted

        // vm.expectRevert(bytes("LiquidityPool/not-owner-or-endorsed"));
        cfgRouter.claimDeposit(vault_, self); // claim Deposit
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

        uint128 assetId = poolManager.assetToId(address(erc20));
        (uint128 trancheTokensPayout) = fulfillDepositRequest(vault, assetId, amount);

        assertEq(vault.maxMint(self), trancheTokensPayout);
        assertEq(vault.maxDeposit(self), amount);
        TrancheTokenLike trancheToken = TrancheTokenLike(address(vault.share()));
        assertEq(trancheToken.balanceOf(address(escrow)), trancheTokensPayout);

        // Any address should be able to call claimDeposit for an investor
        vm.prank(randomUser);
        cfgRouter.claimDeposit(vault_, self);
        assertApproxEqAbs(trancheToken.balanceOf(self), trancheTokensPayout, 1);
        assertApproxEqAbs(trancheToken.balanceOf(address(escrow)), 0, 1);
        assertApproxEqAbs(erc20.balanceOf(address(escrow)), amount, 1);
    }

    function testCFGRouterRedeem(uint256 amount) public {
        amount = uint128(bound(amount, 4, MAX_UINT128));
        vm.assume(amount % 2 == 0);

        // deposit
        address vault_ = deploySimpleVault();
        ERC7540Vault vault = ERC7540Vault(vault_);
        vm.label(vault_, "vault");
        erc20.mint(self, amount);
        erc20.approve(address(cfgRouter), amount);
        centrifugeChain.updateMember(vault.poolId(), vault.trancheId(), self, type(uint64).max); // add user as member
        cfgRouter.requestDeposit(vault_, amount);
        uint128 assetId = poolManager.assetToId(address(erc20));
        (uint128 trancheTokensPayout) = fulfillDepositRequest(vault, assetId, amount);
        TrancheTokenLike trancheToken = TrancheTokenLike(address(vault.share()));
        cfgRouter.claimDeposit(vault_, self);

        // redeem
        trancheToken.approve(address(cfgRouter), trancheTokensPayout);
        cfgRouter.requestRedeem(vault_, trancheTokensPayout);
        (uint128 assetPayout) = fulfillRedeemRequest(vault, assetId, trancheTokensPayout);
        assertApproxEqAbs(trancheToken.balanceOf(self), 0, 1);
        assertApproxEqAbs(trancheToken.balanceOf(address(escrow)), 0, 1);
        assertApproxEqAbs(erc20.balanceOf(address(escrow)), assetPayout, 1);
        assertApproxEqAbs(erc20.balanceOf(self), 0, 1);
        cfgRouter.claimRedeem(vault_, self);
        assertApproxEqAbs(erc20.balanceOf(address(escrow)), 0, 1);
        assertApproxEqAbs(erc20.balanceOf(self), assetPayout, 1);
    }

    function testCFGRouterDepositIntoMultipleVaults(uint256 amount1, uint256 amount2) public {
        amount1 = uint128(bound(amount1, 4, MAX_UINT128));
        vm.assume(amount1 % 2 == 0);
        amount2 = uint128(bound(amount2, 4, MAX_UINT128));
        vm.assume(amount2 % 2 == 0);

        ERC20 erc20X = _newErc20("X's Dollar", "USDX", 6);
        ERC20 erc20Y = _newErc20("Y's Dollar", "USDY", 6);
        vm.label(address(erc20X), "erc20X");
        vm.label(address(erc20Y), "erc20Y");
        address vault1_ =
            deployVault(5, 6, defaultRestrictionSet, "name1", "symbol1", bytes16(bytes("1")), 1, address(erc20X));
        address vault2_ =
            deployVault(4, 6, defaultRestrictionSet, "name2", "symbol2", bytes16(bytes("2")), 2, address(erc20Y));
        ERC7540Vault vault1 = ERC7540Vault(vault1_);
        ERC7540Vault vault2 = ERC7540Vault(vault2_);
        vm.label(vault1_, "vault1");
        vm.label(vault2_, "vault2");

        erc20X.mint(self, amount1);
        erc20Y.mint(self, amount2);

        erc20X.approve(address(cfgRouter), amount1);
        erc20Y.approve(address(cfgRouter), amount2);

        centrifugeChain.updateMember(vault1.poolId(), vault1.trancheId(), self, type(uint64).max);
        centrifugeChain.updateMember(vault2.poolId(), vault2.trancheId(), self, type(uint64).max);
        cfgRouter.requestDeposit(vault1_, amount1);
        cfgRouter.requestDeposit(vault2_, amount2);

        // trigger - deposit order fulfillment
        uint128 assetId1 = poolManager.assetToId(address(erc20X));
        uint128 assetId2 = poolManager.assetToId(address(erc20Y));
        (uint128 trancheTokensPayout1) = fulfillDepositRequest(vault1, assetId1, amount1);
        (uint128 trancheTokensPayout2) = fulfillDepositRequest(vault2, assetId2, amount2);

        assertEq(vault1.maxMint(self), trancheTokensPayout1);
        assertEq(vault2.maxMint(self), trancheTokensPayout2);
        assertEq(vault1.maxDeposit(self), amount1);
        assertEq(vault2.maxDeposit(self), amount2);
        TrancheTokenLike trancheToken1 = TrancheTokenLike(address(vault1.share()));
        TrancheTokenLike trancheToken2 = TrancheTokenLike(address(vault2.share()));
        assertEq(trancheToken1.balanceOf(address(escrow)), trancheTokensPayout1);
        assertEq(trancheToken2.balanceOf(address(escrow)), trancheTokensPayout2);

        cfgRouter.claimDeposit(vault1_, self);
        cfgRouter.claimDeposit(vault2_, self);
        assertApproxEqAbs(trancheToken1.balanceOf(self), trancheTokensPayout1, 1);
        assertApproxEqAbs(trancheToken2.balanceOf(self), trancheTokensPayout2, 1);
        assertApproxEqAbs(trancheToken1.balanceOf(address(escrow)), 0, 1);
        assertApproxEqAbs(trancheToken2.balanceOf(address(escrow)), 0, 1);
        assertApproxEqAbs(erc20X.balanceOf(address(escrow)), amount1, 1);
        assertApproxEqAbs(erc20Y.balanceOf(address(escrow)), amount2, 1);
    }

    function testCFGRouterRedeemFromMultipleVaults(uint256 amount1, uint256 amount2) public {
        amount1 = uint128(bound(amount1, 4, MAX_UINT128));
        vm.assume(amount1 % 2 == 0);
        amount2 = uint128(bound(amount2, 4, MAX_UINT128));
        vm.assume(amount2 % 2 == 0);

        // deposit
        ERC20 erc20X = _newErc20("X's Dollar", "USDX", 6);
        ERC20 erc20Y = _newErc20("Y's Dollar", "USDY", 6);
        vm.label(address(erc20X), "erc20X");
        vm.label(address(erc20Y), "erc20Y");
        address vault1_ =
            deployVault(5, 6, defaultRestrictionSet, "name1", "symbol1", bytes16(bytes("1")), 1, address(erc20X));
        address vault2_ =
            deployVault(4, 6, defaultRestrictionSet, "name2", "symbol2", bytes16(bytes("2")), 2, address(erc20Y));
        ERC7540Vault vault1 = ERC7540Vault(vault1_);
        ERC7540Vault vault2 = ERC7540Vault(vault2_);
        vm.label(vault1_, "vault1");
        vm.label(vault2_, "vault2");
        erc20X.mint(self, amount1);
        erc20Y.mint(self, amount2);
        erc20X.approve(address(cfgRouter), amount1);
        erc20Y.approve(address(cfgRouter), amount2);
        centrifugeChain.updateMember(vault1.poolId(), vault1.trancheId(), self, type(uint64).max);
        centrifugeChain.updateMember(vault2.poolId(), vault2.trancheId(), self, type(uint64).max);
        cfgRouter.requestDeposit(vault1_, amount1);
        cfgRouter.requestDeposit(vault2_, amount2);
        uint128 assetId1 = poolManager.assetToId(address(erc20X));
        uint128 assetId2 = poolManager.assetToId(address(erc20Y));
        (uint128 trancheTokensPayout1) = fulfillDepositRequest(vault1, assetId1, amount1);
        (uint128 trancheTokensPayout2) = fulfillDepositRequest(vault2, assetId2, amount2);
        TrancheTokenLike trancheToken1 = TrancheTokenLike(address(vault1.share()));
        TrancheTokenLike trancheToken2 = TrancheTokenLike(address(vault2.share()));
        cfgRouter.claimDeposit(vault1_, self);
        cfgRouter.claimDeposit(vault2_, self);

        // redeem
        trancheToken1.approve(address(cfgRouter), trancheTokensPayout1);
        trancheToken2.approve(address(cfgRouter), trancheTokensPayout2);
        cfgRouter.requestRedeem(vault1_, trancheTokensPayout1);
        cfgRouter.requestRedeem(vault2_, trancheTokensPayout2);
        (uint128 assetPayout1) = fulfillRedeemRequest(vault1, assetId1, trancheTokensPayout1);
        (uint128 assetPayout2) = fulfillRedeemRequest(vault2, assetId2, trancheTokensPayout2);
        assertApproxEqAbs(trancheToken1.balanceOf(self), 0, 1);
        assertApproxEqAbs(trancheToken2.balanceOf(self), 0, 1);
        assertApproxEqAbs(trancheToken1.balanceOf(address(escrow)), 0, 1);
        assertApproxEqAbs(trancheToken2.balanceOf(address(escrow)), 0, 1);
        assertApproxEqAbs(erc20X.balanceOf(address(escrow)), assetPayout1, 1);
        assertApproxEqAbs(erc20Y.balanceOf(address(escrow)), assetPayout2, 1);
        assertApproxEqAbs(erc20X.balanceOf(self), 0, 1);
        assertApproxEqAbs(erc20Y.balanceOf(self), 0, 1);
        cfgRouter.claimRedeem(vault1_, self);
        cfgRouter.claimRedeem(vault2_, self);
        assertApproxEqAbs(erc20X.balanceOf(address(escrow)), 0, 1);
        assertApproxEqAbs(erc20Y.balanceOf(address(escrow)), 0, 1);
        assertApproxEqAbs(erc20X.balanceOf(self), assetPayout1, 1);
        assertApproxEqAbs(erc20Y.balanceOf(self), assetPayout2, 1);
    }

    function testMulticallingDepositClaimAndRequestRedeem(uint256 amount) public {
        amount = uint128(bound(amount, 4, MAX_UINT128));
        vm.assume(amount % 2 == 0);

        // deposit
        address vault_ = deploySimpleVault();
        ERC7540Vault vault = ERC7540Vault(vault_);
        vm.label(vault_, "vault");
        erc20.mint(self, amount);
        erc20.approve(address(cfgRouter), amount);
        centrifugeChain.updateMember(vault.poolId(), vault.trancheId(), self, type(uint64).max); // add user as member
        cfgRouter.requestDeposit(vault_, amount);
        uint128 assetId = poolManager.assetToId(address(erc20));
        (uint128 trancheTokensPayout) = fulfillDepositRequest(vault, assetId, amount);
        TrancheTokenLike trancheToken = TrancheTokenLike(address(vault.share()));
        trancheToken.approve(address(cfgRouter), trancheTokensPayout);

        // multicall
        Call[] memory calls = new Call[](2);
        calls[0] = Call(address(cfgRouter), abi.encodeWithSelector(cfgRouter.claimDeposit.selector, vault_, self));
        calls[1] = Call(
            address(cfgRouter),
            abi.encodeWithSelector(
                bytes4(keccak256("requestRedeem(address,uint256,address)")), vault_, trancheTokensPayout, self
            )
        );
        MockMulticall multicall = new MockMulticall();
        multicall.aggregate(calls);

        (uint128 assetPayout) = fulfillRedeemRequest(vault, assetId, trancheTokensPayout);
        assertApproxEqAbs(trancheToken.balanceOf(self), 0, 1);
        assertApproxEqAbs(trancheToken.balanceOf(address(escrow)), 0, 1);
        assertApproxEqAbs(erc20.balanceOf(address(escrow)), assetPayout, 1);
        assertApproxEqAbs(erc20.balanceOf(self), 0, 1);
    }

    // --- helpers ---
    function fulfillDepositRequest(ERC7540Vault vault, uint128 assetId, uint256 amount)
        public
        returns (uint128 trancheTokensPayout)
    {
        uint128 price = 2 * 10 ** 18;
        trancheTokensPayout = uint128(amount * 10 ** 18 / price);
        assertApproxEqAbs(trancheTokensPayout, amount / 2, 2);
        centrifugeChain.isFulfilledDepositRequest(
            vault.poolId(),
            vault.trancheId(),
            bytes32(bytes20(self)),
            assetId,
            uint128(amount),
            trancheTokensPayout,
            uint128(amount)
        );
    }

    function fulfillRedeemRequest(ERC7540Vault vault, uint128 assetId, uint256 amount)
        public
        returns (uint128 assetPayout)
    {
        uint128 price = 2 * 10 ** 18;
        assetPayout = uint128(amount * price / 10 ** 18);
        assertApproxEqAbs(assetPayout, amount * 2, 2);
        centrifugeChain.isFulfilledRedeemRequest(
            vault.poolId(), vault.trancheId(), bytes32(bytes20(self)), assetId, assetPayout, uint128(amount)
        );
    }
}
