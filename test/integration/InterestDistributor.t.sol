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
        ITranche tranche = ITranche(address(vault.share()));

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

        assertApproxEqAbs(vault.pendingRedeemRequest(0, investor), 0, 1);
        assertApproxEqAbs(interestDistributor.pending(vault_, investor), 0, 1);

        vm.expectRevert(bytes("InterestDistributor/not-an-operator"));
        interestDistributor.distribute(vault_, investor);

        vm.prank(investor);
        vault.setOperator(address(interestDistributor), true);

        interestDistributor.distribute(vault_, investor);

        assertApproxEqAbs(vault.pendingRedeemRequest(0, investor), 0, 1);
        assertApproxEqAbs(interestDistributor.pending(vault_, investor), 0, 1);

        vm.warp(block.timestamp + 1 days);
        centrifugeChain.updateTranchePrice(
            vault.poolId(), vault.trancheId(), defaultAssetId, 1.1 * 10 ** 18, uint64(block.timestamp)
        );

        assertApproxEqAbs(vault.pendingRedeemRequest(0, investor), 0, 1);
        assertApproxEqAbs(interestDistributor.pending(vault_, investor), amount / 10, 1);

        interestDistributor.distribute(vault_, investor);

        assertApproxEqAbs(vault.pendingRedeemRequest(0, investor), amount / 10, 1);
        assertApproxEqAbs(interestDistributor.pending(vault_, investor), 0, 1);

        // vm.warp(block.timestamp + 1 days);
        // centrifugeChain.updateTranchePrice(
        //     vault.poolId(), vault.trancheId(), defaultAssetId, 1.0 * 10 ** 18, uint64(block.timestamp)
        // );

        // assertApproxEqAbs(interestDistributor.pending(vault_, investor), 0, 1);
        // interestDistributor.distribute(vault_, investor);

        // vm.warp(block.timestamp + 1 days);
        // centrifugeChain.updateTranchePrice(
        //     vault.poolId(), vault.trancheId(), defaultAssetId, 2 * 10 ** 18, uint64(block.timestamp)
        // );

        // assertApproxEqAbs(interestDistributor.pending(vault_, investor), amount / 2, 1);
    }
}
