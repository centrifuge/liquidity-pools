// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import "test/BaseTest.sol";

contract OperatorTest is BaseTest {
    function testDepositAsOperator(uint256 amount) public {
        // If lower than 4 or odd, rounding down can lead to not receiving any tokens
        amount = uint128(bound(amount, 4, MAX_UINT128));
        vm.assume(amount % 2 == 0);

        uint128 price = 2 * 10 ** 18;
        address vault_ = deploySimpleVault();
        address investor = makeAddr("investor");
        address operator = makeAddr("operator");
        ERC7540Vault vault = ERC7540Vault(vault_);
        ITrancheToken trancheToken = ITrancheToken(address(vault.share()));

        centrifugeChain.updateTrancheTokenPrice(
            vault.poolId(), vault.trancheId(), defaultAssetId, price, uint64(block.timestamp)
        );

        erc20.mint(investor, amount);

        centrifugeChain.updateMember(vault.poolId(), vault.trancheId(), investor, type(uint64).max);
        vm.prank(investor);
        erc20.approve(vault_, amount);

        vm.prank(operator);
        vm.expectRevert(bytes("ERC7540Vault/invalid-owner"));
        vault.requestDeposit(amount, investor, investor);

        assertEq(vault.isOperator(investor, operator), false);
        vm.prank(investor);
        vault.setOperator(operator, true);
        assertEq(vault.isOperator(investor, operator), true);

        vm.prank(operator);
        vault.requestDeposit(amount, investor, investor);
        assertEq(vault.pendingDepositRequest(0, investor), amount);
        assertEq(vault.pendingDepositRequest(0, operator), 0);

        centrifugeChain.isFulfilledDepositRequest(
            vault.poolId(),
            vault.trancheId(),
            bytes32(bytes20(investor)),
            defaultAssetId,
            uint128(amount),
            uint128(amount),
            uint128(amount)
        );

        vm.prank(operator);
        vault.deposit(amount, investor, investor);
        assertEq(vault.pendingDepositRequest(0, investor), 0);
        assertEq(trancheToken.balanceOf(investor), amount);

        vm.prank(investor);
        vault.setOperator(operator, false);

        vm.prank(operator);
        vm.expectRevert(bytes("ERC7540Vault/invalid-owner"));
        vault.requestDeposit(amount, investor, investor);
    }

    function testDepositAsAuthorizedOperator(uint256 amount) public {
        // If lower than 4 or odd, rounding down can lead to not receiving any tokens
        amount = uint128(bound(amount, 4, MAX_UINT128));
        vm.assume(amount % 2 == 0);

        uint128 price = 2 * 10 ** 18;
        address vault_ = deploySimpleVault();
        (address owner, uint256 ownerPk) = makeAddrAndKey("owner");
        address operator = makeAddr("operator");
        ERC7540Vault vault = ERC7540Vault(vault_);

        centrifugeChain.updateTrancheTokenPrice(
            vault.poolId(), vault.trancheId(), defaultAssetId, price, uint64(block.timestamp)
        );

        erc20.mint(owner, amount);

        centrifugeChain.updateMember(vault.poolId(), vault.trancheId(), owner, type(uint64).max);
        vm.prank(owner);
        erc20.approve(vault_, amount);

        vm.prank(operator);
        vm.expectRevert(bytes("ERC7540Vault/invalid-owner"));
        vault.requestDeposit(amount, owner, owner);

        uint256 deadline = type(uint64).max;
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            ownerPk,
            keccak256(
                abi.encodePacked(
                    "\x19\x01",
                    vault.DOMAIN_SEPARATOR(),
                    keccak256(
                        abi.encode(
                            vault.AUTHORIZE_OPERATOR_TYPEHASH(), owner, operator, true, deadline, bytes32("nonce")
                        )
                    )
                )
            )
        );
        bytes memory signature = abi.encodePacked(r, s, v);
        delete r;
        delete s;
        delete v;

        assertEq(vault.isOperator(owner, operator), false);
        vm.prank(operator);
        vault.authorizeOperator(owner, operator, true, deadline, bytes32("nonce"), signature);
        assertEq(vault.isOperator(owner, operator), true);

        vm.prank(operator);
        vault.requestDeposit(amount, owner, owner);
        assertEq(vault.pendingDepositRequest(0, owner), amount);
        assertEq(vault.pendingDepositRequest(0, operator), 0);
    }

    function testRedeemAsOperator(uint256 amount) public {
        // If lower than 4 or odd, rounding down can lead to not receiving any tokens
        amount = uint128(bound(amount, 4, MAX_UINT128 / 2));
        vm.assume(amount % 2 == 0);

        address vault_ = deploySimpleVault();
        address investor = makeAddr("investor");
        address operator = makeAddr("operator");
        ERC7540Vault vault = ERC7540Vault(vault_);

        deposit(vault_, investor, amount); // deposit funds first
        centrifugeChain.updateTrancheTokenPrice(
            vault.poolId(), vault.trancheId(), defaultAssetId, defaultPrice, uint64(block.timestamp)
        );

        vm.prank(operator);
        vm.expectRevert(bytes("ERC20/insufficient-allowance"));
        vault.requestRedeem(amount, investor, investor);

        assertEq(vault.isOperator(investor, operator), false);
        vm.prank(investor);
        vault.setOperator(operator, true);
        assertEq(vault.isOperator(investor, operator), true);

        vm.prank(operator);
        vault.requestRedeem(amount, investor, investor);
        assertEq(vault.pendingRedeemRequest(0, investor), amount);
        assertEq(vault.pendingRedeemRequest(0, operator), 0);

        centrifugeChain.isFulfilledRedeemRequest(
            vault.poolId(),
            vault.trancheId(),
            bytes32(bytes20(investor)),
            defaultAssetId,
            uint128(amount),
            uint128(amount)
        );

        vm.prank(operator);
        vault.redeem(amount, investor, investor);
        assertEq(vault.pendingRedeemRequest(0, investor), 0);
        assertEq(erc20.balanceOf(investor), amount);

        vm.prank(investor);
        vault.setOperator(operator, false);

        deposit(vault_, investor, amount);
        vm.prank(operator);
        vm.expectRevert(bytes("ERC20/insufficient-allowance"));
        vault.requestRedeem(amount, investor, investor);
    }
}
