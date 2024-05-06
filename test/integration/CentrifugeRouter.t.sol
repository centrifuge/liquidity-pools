// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import "test/BaseTest.sol";
import "src/interfaces/IERC7575.sol";
import "src/interfaces/IERC7540.sol";
import {SucceedingRequestReceiver} from "test/mocks/SucceedingRequestReceiver.sol";
import {FailingRequestReceiver} from "test/mocks/FailingRequestReceiver.sol";

contract CentriufgeRoutertest is BaseTest {
    function testCFGRouterDeposit(uint256 amount) public {
        // If lower than 4 or odd, rounding down can lead to not receiving any tokens
        amount = uint128(bound(amount, 4, MAX_UINT128));
        vm.assume(amount % 2 == 0);

        address vault_ = deploySimpleVault();
        ERC7540Vault vault = ERC7540Vault(vault_);

        // centrifugeChain.updateTrancheTokenPrice(
        //         vault.poolId(), vault.trancheId(), defaultAssetId, price, uint64(block.timestamp)
        // );

        erc20.mint(self, amount);

        vm.expectRevert(bytes("SafeTransferLib/safe-transfer-from-failed")); // fail: no allowance
        cfgRouter.requestDeposit(vault_, amount);

        erc20.approve(address(cfgRouter), amount); // grant approval to cfg router

        vm.expectRevert(bytes("InvestmentManager/transfer-not-allowed")); // fail: receiver not member
        cfgRouter.requestDeposit(vault_, amount);

        centrifugeChain.updateMember(vault.poolId(), vault.trancheId(), self, type(uint64).max); // add user as member
        cfgRouter.requestDeposit(vault_, amount);

        // trigger - deposit order fulfillment
        uint128 price = 2 * 10 ** 18;
        uint128 _currencyId = poolManager.assetToId(address(erc20)); // retrieve currencyId
        uint128 trancheTokensPayout = uint128(amount * 10 ** 18 / price); // trancheTokenPrice = 2$
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
}
