// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import "test/BaseTest.sol";
import "src/interfaces/IERC7575.sol";
import "src/interfaces/IERC7540.sol";
import {SucceedingRequestReceiver} from "test/mocks/SucceedingRequestReceiver.sol";
import {FailingRequestReceiver} from "test/mocks/FailingRequestReceiver.sol";

contract ERC7540VaultTest is BaseTest {
    // Deployment
    function testDeployment(
        uint64 poolId,
        string memory tokenName,
        string memory tokenSymbol,
        bytes16 trancheId,
        uint128 assetId,
        address nonWard
    ) public {
        vm.assume(nonWard != address(root) && nonWard != address(this) && nonWard != address(investmentManager));
        vm.assume(assetId > 0);
        vm.assume(bytes(tokenName).length <= 128);
        vm.assume(bytes(tokenSymbol).length <= 32);

        address vault_ = deployVault(poolId, erc20.decimals(), tokenName, tokenSymbol, trancheId, assetId);
        ERC7540Vault vault = ERC7540Vault(vault_);

        // values set correctly
        assertEq(address(vault.manager()), address(investmentManager));
        assertEq(vault.asset(), address(erc20));
        assertEq(vault.poolId(), poolId);
        assertEq(vault.trancheId(), trancheId);
        address token = poolManager.getTrancheToken(poolId, trancheId);
        assertEq(address(vault.share()), token);
        assertEq(tokenName, ERC20(token).name());
        assertEq(tokenSymbol, ERC20(token).symbol());

        // permissions set correctly
        assertEq(vault.wards(address(root)), 1);
        assertEq(vault.wards(address(investmentManager)), 1);
        assertEq(vault.wards(nonWard), 0);
    }

    // --- Administration ---
    function testFile() public {
        address vault_ = deploySimpleVault();
        ERC7540Vault vault = ERC7540Vault(vault_);

        vm.expectRevert(bytes("Auth/not-authorized"));
        vault.file("manager", self);

        root.relyContract(vault_, self);
        vault.file("manager", self);

        vm.expectRevert(bytes("ERC7540Vault/file-unrecognized-param"));
        vault.file("random", self);
    }

    // --- uint128 type checks ---
    // Make sure all function calls would fail when overflow uint128
    function testAssertUint128(uint256 amount) public {
        vm.assume(amount > MAX_UINT128); // amount has to overflow UINT128
        address vault_ = deploySimpleVault();
        ERC7540Vault vault = ERC7540Vault(vault_);

        vm.expectRevert(bytes("MathLib/uint128-overflow"));
        vault.convertToShares(amount);

        vm.expectRevert(bytes("MathLib/uint128-overflow"));
        vault.convertToAssets(amount);

        vm.expectRevert(bytes("MathLib/uint128-overflow"));
        vault.deposit(amount, randomUser);

        vm.expectRevert(bytes("MathLib/uint128-overflow"));
        vault.mint(amount, randomUser);

        vm.expectRevert(bytes("MathLib/uint128-overflow"));
        vault.withdraw(amount, randomUser, self);

        vm.expectRevert(bytes("MathLib/uint128-overflow"));
        vault.redeem(amount, randomUser, self);

        erc20.mint(address(this), amount);
        vm.expectRevert(bytes("MathLib/uint128-overflow"));
        vault.requestDeposit(amount, self, self, "");

        TrancheTokenLike trancheToken = TrancheTokenLike(address(vault.share()));
        centrifugeChain.updateMember(vault.poolId(), vault.trancheId(), self, type(uint64).max);
        root.relyContract(address(trancheToken), self);
        trancheToken.mint(address(this), amount);
        vm.expectRevert(bytes("MathLib/uint128-overflow"));
        vault.requestRedeem(amount, address(this), address(this), "");
    }

    // --- erc165 checks ---
    function testERC165Support(bytes4 unsupportedInterfaceId) public {
        bytes4 erc165 = 0x01ffc9a7;
        bytes4 erc7575 = 0x2f0a18c5;
        bytes4 erc7540Deposit = 0x1683f250;
        bytes4 erc7540Redeem = 0x0899cb0b;

        vm.assume(
            unsupportedInterfaceId != erc165 && unsupportedInterfaceId != erc7575
                && unsupportedInterfaceId != erc7540Deposit && unsupportedInterfaceId != erc7540Redeem
        );

        address vault_ = deploySimpleVault();
        ERC7540Vault vault = ERC7540Vault(vault_);

        assertEq(type(IERC165).interfaceId, erc165);
        assertEq(type(IERC7575).interfaceId, erc7575);
        assertEq(type(IERC7540Deposit).interfaceId, erc7540Deposit);
        assertEq(type(IERC7540Redeem).interfaceId, erc7540Redeem);

        assertEq(vault.supportsInterface(erc165), true);
        assertEq(vault.supportsInterface(erc7575), true);
        assertEq(vault.supportsInterface(erc7540Deposit), true);
        assertEq(vault.supportsInterface(erc7540Redeem), true);

        assertEq(vault.supportsInterface(unsupportedInterfaceId), false);
    }

    // --- callbacks ---
    function testSucceedingCallbacks(bytes memory depositData, bytes memory redeemData) public {
        vm.assume(depositData.length > 0);
        vm.assume(redeemData.length > 0);

        address vault_ = deploySimpleVault();
        ERC7540Vault vault = ERC7540Vault(vault_);
        SucceedingRequestReceiver receiver = new SucceedingRequestReceiver();

        centrifugeChain.updateMember(vault.poolId(), vault.trancheId(), address(receiver), type(uint64).max);
        centrifugeChain.updateMember(vault.poolId(), vault.trancheId(), self, type(uint64).max);

        uint256 amount = 100 * 10 ** 6;
        erc20.mint(self, amount);
        erc20.approve(vault_, amount);

        // Check deposit callback
        vault.requestDeposit(amount, address(receiver), self, depositData);

        assertEq(erc20.balanceOf(self), 0);
        assertEq(receiver.values_address("requestDeposit_operator"), self);
        assertEq(receiver.values_address("requestDeposit_owner"), self);
        assertEq(receiver.values_uint256("requestDeposit_requestId"), 0);
        assertEq(receiver.values_uint256("requestDeposit_assets"), amount);
        assertEq(receiver.values_bytes("requestDeposit_data"), depositData);

        assertTrue(receiver.onERC7540DepositReceived(self, self, 0, amount, depositData) == 0x6d7e2da0);

        // Claim deposit request
        // Note this is sending it to self, which is technically incorrect, it should be going to the receiver
        centrifugeChain.isFulfilledDepositRequest(
            vault.poolId(),
            vault.trancheId(),
            bytes32(bytes20(self)),
            defaultAssetId,
            uint128(amount),
            uint128(amount),
            0
        );
        vault.mint(vault.maxMint(self), self);

        // Check redeem callback
        vault.requestRedeem(amount, address(receiver), self, redeemData);

        TrancheToken trancheToken = TrancheToken(address(vault.share()));
        assertEq(trancheToken.balanceOf(self), 0);
        assertEq(receiver.values_address("requestRedeem_operator"), self);
        assertEq(receiver.values_address("requestRedeem_owner"), self);
        assertEq(receiver.values_uint256("requestRedeem_requestId"), 0);
        assertEq(receiver.values_uint256("requestRedeem_shares"), amount);
        assertEq(receiver.values_bytes("requestRedeem_data"), redeemData);

        assertTrue(receiver.onERC7540RedeemReceived(self, self, 0, amount, redeemData) == 0x01a2e97e);
    }

    function testSucceedingCallbacksNotCalledWithEmptyData() public {
        address vault_ = deploySimpleVault();
        ERC7540Vault vault = ERC7540Vault(vault_);
        SucceedingRequestReceiver receiver = new SucceedingRequestReceiver();

        centrifugeChain.updateMember(vault.poolId(), vault.trancheId(), address(receiver), type(uint64).max);
        centrifugeChain.updateMember(vault.poolId(), vault.trancheId(), self, type(uint64).max);

        uint256 amount = 100 * 10 ** 6;
        erc20.mint(self, amount);
        erc20.approve(vault_, amount);

        // Check deposit callback
        vault.requestDeposit(amount, address(receiver), self, "");

        assertEq(receiver.values_address("requestDeposit_operator"), address(0));
        assertEq(receiver.values_address("requestDeposit_owner"), address(0));
        assertEq(receiver.values_uint256("requestDeposit_requestId"), 0);
        assertEq(receiver.values_uint256("requestDeposit_assets"), 0);
        assertEq(receiver.values_bytes("requestDeposit_data"), "");

        // Claim deposit request
        // Note this is sending it to self, which is technically incorrect, it should be going to the receiver
        centrifugeChain.isFulfilledDepositRequest(
            vault.poolId(),
            vault.trancheId(),
            bytes32(bytes20(self)),
            defaultAssetId,
            uint128(amount),
            uint128(amount),
            0
        );
        vault.mint(vault.maxMint(self), self);

        // Check redeem callback
        vault.requestRedeem(amount, address(receiver), self, "");

        TrancheToken trancheToken = TrancheToken(address(vault.share()));
        assertEq(trancheToken.balanceOf(self), 0);
        assertEq(receiver.values_address("requestRedeem_operator"), address(0));
        assertEq(receiver.values_address("requestRedeem_owner"), address(0));
        assertEq(receiver.values_uint256("requestRedeem_requestId"), 0);
        assertEq(receiver.values_uint256("requestRedeem_shares"), 0);
        assertEq(receiver.values_bytes("requestRedeem_data"), "");
    }

    function testFailingCallbacks(bytes memory depositData, bytes memory redeemData) public {
        address vault_ = deploySimpleVault();
        ERC7540Vault vault = ERC7540Vault(vault_);
        FailingRequestReceiver receiver = new FailingRequestReceiver();

        centrifugeChain.updateMember(vault.poolId(), vault.trancheId(), address(receiver), type(uint64).max);
        centrifugeChain.updateMember(vault.poolId(), vault.trancheId(), self, type(uint64).max);

        uint256 amount = 100 * 10 ** 6;
        erc20.mint(self, amount);
        erc20.approve(vault_, amount);

        // Check deposit callback
        vm.expectRevert(bytes("ERC7540Vault/receiver-failed"));
        vault.requestDeposit(amount, address(receiver), self, depositData);

        assertEq(erc20.balanceOf(self), amount);
        assertEq(receiver.values_address("requestDeposit_operator"), self);
        assertEq(receiver.values_address("requestDeposit_owner"), self);
        assertEq(receiver.values_uint256("requestDeposit_requestId"), 0);
        assertEq(receiver.values_uint256("requestDeposit_assets"), amount);
        assertEq(receiver.values_bytes("requestDeposit_data"), depositData);

        // Re-submit and claim deposit request
        vault.requestDeposit(amount, self, self, depositData);
        centrifugeChain.isFulfilledDepositRequest(
            vault.poolId(),
            vault.trancheId(),
            bytes32(bytes20(self)),
            defaultAssetId,
            uint128(amount),
            uint128(amount),
            0
        );
        vault.mint(vault.maxMint(self), self);

        // Check redeem callback
        vm.expectRevert(bytes("ERC7540Vault/receiver-failed"));
        vault.requestRedeem(amount, address(receiver), self, redeemData);

        assertEq(erc20.balanceOf(self), amount);
        assertEq(receiver.values_address("requestRedeem_operator"), self);
        assertEq(receiver.values_address("requestRedeem_owner"), self);
        assertEq(receiver.values_uint256("requestRedeem_requestId"), 0);
        assertEq(receiver.values_uint256("requestDeposit_shares"), amount);
        assertEq(receiver.values_bytes("requestRedeem_data"), redeemData);
    }

    // --- preview checks ---
    function testPreviewReverts(uint256 amount) public {
        vm.assume(amount > MAX_UINT128); // amount has to overflow UINT128
        address vault_ = deploySimpleVault();
        ERC7540Vault vault = ERC7540Vault(vault_);

        vm.expectRevert(bytes(""));
        vault.previewDeposit(amount);

        vm.expectRevert(bytes(""));
        vault.previewRedeem(amount);

        vm.expectRevert(bytes(""));
        vault.previewMint(amount);

        vm.expectRevert(bytes(""));
        vault.previewWithdraw(amount);
    }
}
