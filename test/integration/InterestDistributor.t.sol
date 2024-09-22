// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.26;

import "test/BaseTest.sol";

contract InterestDistributorTest is BaseTest {
    function testDistributeInterest(uint256 amount) public {
        // If lower than 4 or odd, rounding down can lead to not receiving any tokens
        amount = uint128(bound(amount, 4, MAX_UINT128));
        vm.assume(amount % 2 == 0);

        uint128 price = 1 * 10 ** 18;
        address vault_ = deploySimpleVault();
        address investor = makeAddr("investor");
        ERC7540Vault vault = ERC7540Vault(vault_);

        centrifugeChain.updateTranchePrice(
            vault.poolId(), vault.trancheId(), defaultAssetId, price, uint64(block.timestamp)
        );

        erc20.mint(investor, amount);

        centrifugeChain.updateMember(vault.poolId(), vault.trancheId(), investor, type(uint64).max);
        vm.prank(investor);
        erc20.approve(vault_, amount);

        vm.prank(investor);
        vault.requestDeposit(amount, investor, investor);

        centrifugeChain.isFulfilledDepositRequest(
            vault.poolId(),
            vault.trancheId(),
            bytes32(bytes20(investor)),
            defaultAssetId,
            uint128(amount),
            uint128(amount)
        );

        vm.prank(investor);
        vault.deposit(amount, investor, investor);

        // Initially, pending interest is 0
        assertApproxEqAbs(vault.pendingRedeemRequest(0, investor), 0, 1);
        assertApproxEqAbs(interestDistributor.pending(vault_, investor), 0, 1);

        vm.expectRevert(bytes("InterestDistributor/not-an-operator"));
        interestDistributor.distribute(vault_, investor);

        vm.prank(investor);
        vault.setOperator(address(interestDistributor), true);

        interestDistributor.distribute(vault_, investor);

        assertApproxEqAbs(vault.pendingRedeemRequest(0, investor), 0, 1);
        assertApproxEqAbs(interestDistributor.pending(vault_, investor), 0, 1);

        // Once price goes to 1.25, 1/5th of the total shares are redeemed
        vm.warp(block.timestamp + 1 days);
        centrifugeChain.updateTranchePrice(
            vault.poolId(), vault.trancheId(), defaultAssetId, 1.25 * 10 ** 18, uint64(block.timestamp)
        );

        assertApproxEqAbs(vault.pendingRedeemRequest(0, investor), 0, 1);
        assertApproxEqAbs(interestDistributor.pending(vault_, investor), amount / 5, 1);

        interestDistributor.distribute(vault_, investor);

        assertApproxEqAbs(vault.pendingRedeemRequest(0, investor), amount / 5, 1);
        assertApproxEqAbs(interestDistributor.pending(vault_, investor), 0, 1);

        // When price goes down, no new redemption is submitted
        vm.warp(block.timestamp + 1 days);
        centrifugeChain.updateTranchePrice(
            vault.poolId(), vault.trancheId(), defaultAssetId, 1.0 * 10 ** 18, uint64(block.timestamp)
        );

        assertApproxEqAbs(interestDistributor.pending(vault_, investor), 0, 1);
        interestDistributor.distribute(vault_, investor);

        vm.warp(block.timestamp + 1 days);
        centrifugeChain.updateTranchePrice(
            vault.poolId(), vault.trancheId(), defaultAssetId, 1.1 * 10 ** 18, uint64(block.timestamp)
        );

        assertApproxEqAbs(interestDistributor.pending(vault_, investor), 0, 1);
        interestDistributor.distribute(vault_, investor);

        // Once price goes above 1.25 (to 2.50) again, shares are redeemed
        vm.warp(block.timestamp + 1 days);
        centrifugeChain.updateTranchePrice(
            vault.poolId(), vault.trancheId(), defaultAssetId, 2.5 * 10 ** 18, uint64(block.timestamp)
        );

        assertApproxEqAbs(interestDistributor.pending(vault_, investor), (amount - amount / 5) / 2, 1);
    }

    // TODO: testDistributeAfterAnotherDeposit
    // TODO: testDistributeAfterPrincipalRedemption
    // TODO: testClear
}
