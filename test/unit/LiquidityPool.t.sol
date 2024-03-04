// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import "test/BaseTest.sol";
import "src/interfaces/IERC7575.sol";
import "src/interfaces/IERC7540.sol";
import {SucceedingRequestReceiver} from "test/mocks/SucceedingRequestReceiver.sol";
import {FailingRequestReceiver} from "test/mocks/FailingRequestReceiver.sol";

contract LiquidityPoolTest is BaseTest {
    // Deployment
    function testDeployment(
        uint64 poolId,
        string memory tokenName,
        string memory tokenSymbol,
        bytes16 trancheId,
        uint128 currencyId,
        address nonWard
    ) public {
        vm.assume(nonWard != address(root) && nonWard != address(this));
        vm.assume(currencyId > 0);
        vm.assume(bytes(tokenName).length <= 128);
        vm.assume(bytes(tokenSymbol).length <= 32);

        address lPool_ = deployLiquidityPool(poolId, erc20.decimals(), tokenName, tokenSymbol, trancheId, currencyId);
        LiquidityPool lPool = LiquidityPool(lPool_);

        // values set correctly
        assertEq(address(lPool.manager()), address(investmentManager));
        assertEq(lPool.asset(), address(erc20));
        assertEq(lPool.poolId(), poolId);
        assertEq(lPool.trancheId(), trancheId);
        address token = poolManager.getTrancheToken(poolId, trancheId);
        assertEq(address(lPool.share()), token);
        assertEq(tokenName, ERC20(token).name());
        assertEq(tokenSymbol, ERC20(token).symbol());

        // permissions set correctly
        assertEq(lPool.wards(address(root)), 1);
        assertEq(lPool.wards(nonWard), 0);
    }

    // --- Administration ---
    function testFile() public {
        address lPool_ = deploySimplePool();
        LiquidityPool lPool = LiquidityPool(lPool_);

        vm.expectRevert(bytes("Auth/not-authorized"));
        lPool.file("manager", self);

        root.relyContract(lPool_, self);
        lPool.file("manager", self);

        vm.expectRevert(bytes("LiquidityPool/file-unrecognized-param"));
        lPool.file("random", self);
    }

    // --- uint128 type checks ---
    // Make sure all function calls would fail when overflow uint128
    function testAssertUint128(uint256 amount) public {
        vm.assume(amount > MAX_UINT128); // amount has to overflow UINT128
        address lPool_ = deploySimplePool();
        LiquidityPool lPool = LiquidityPool(lPool_);

        vm.expectRevert(bytes("MathLib/uint128-overflow"));
        lPool.convertToShares(amount);

        vm.expectRevert(bytes("MathLib/uint128-overflow"));
        lPool.convertToAssets(amount);

        vm.expectRevert(bytes("MathLib/uint128-overflow"));
        lPool.deposit(amount, randomUser);

        vm.expectRevert(bytes("MathLib/uint128-overflow"));
        lPool.mint(amount, randomUser);

        vm.expectRevert(bytes("MathLib/uint128-overflow"));
        lPool.withdraw(amount, randomUser, self);

        vm.expectRevert(bytes("MathLib/uint128-overflow"));
        lPool.redeem(amount, randomUser, self);

        erc20.mint(address(this), amount);
        vm.expectRevert(bytes("MathLib/uint128-overflow"));
        lPool.requestDeposit(amount, self, self, "");

        TrancheTokenLike trancheToken = TrancheTokenLike(address(lPool.share()));
        centrifugeChain.updateMember(lPool.poolId(), lPool.trancheId(), self, type(uint64).max);
        root.relyContract(address(trancheToken), self);
        trancheToken.mint(address(this), amount);
        vm.expectRevert(bytes("MathLib/uint128-overflow"));
        lPool.requestRedeem(amount, address(this), address(this), "");
    }

    // --- erc165 checks ---
    function testERC165Support(bytes4 unsupportedInterfaceId) public {
        bytes4 erc165 = 0x01ffc9a7;
        bytes4 erc7575 = 0x2f0a18c5;
        bytes4 erc7575Minimal = 0x50a526d6;
        bytes4 erc7575Deposit = 0xc1f329ef;
        bytes4 erc7575Mint = 0xe1550342;
        bytes4 erc7575Withdraw = 0x70dec094;
        bytes4 erc7575Redeem = 0x2fd7d42a;
        bytes4 erc7540Deposit = 0x1683f250;
        bytes4 erc7540Redeem = 0x0899cb0b;

        vm.assume(
            unsupportedInterfaceId != erc165 && unsupportedInterfaceId != erc7575
                && unsupportedInterfaceId != erc7575Minimal && unsupportedInterfaceId != erc7575Deposit
                && unsupportedInterfaceId != erc7575Mint && unsupportedInterfaceId != erc7575Withdraw
                && unsupportedInterfaceId != erc7575Redeem && unsupportedInterfaceId != erc7540Deposit
                && unsupportedInterfaceId != erc7540Redeem
        );

        address lPool_ = deploySimplePool();
        LiquidityPool lPool = LiquidityPool(lPool_);

        assertEq(type(IERC165).interfaceId, erc165);
        assertEq(type(IERC7575).interfaceId, erc7575);
        assertEq(type(IERC7575Minimal).interfaceId, erc7575Minimal);
        assertEq(type(IERC7575Deposit).interfaceId, erc7575Deposit);
        assertEq(type(IERC7575Mint).interfaceId, erc7575Mint);
        assertEq(type(IERC7575Withdraw).interfaceId, erc7575Withdraw);
        assertEq(type(IERC7575Redeem).interfaceId, erc7575Redeem);
        assertEq(type(IERC7540Deposit).interfaceId, erc7540Deposit);
        assertEq(type(IERC7540Redeem).interfaceId, erc7540Redeem);

        assertEq(lPool.supportsInterface(erc165), true);
        assertEq(lPool.supportsInterface(erc7575), true);
        assertEq(lPool.supportsInterface(erc7575Minimal), true);
        assertEq(lPool.supportsInterface(erc7575Deposit), true);
        assertEq(lPool.supportsInterface(erc7575Mint), true);
        assertEq(lPool.supportsInterface(erc7575Redeem), true);
        assertEq(lPool.supportsInterface(erc7575Minimal), true);
        assertEq(lPool.supportsInterface(erc7540Deposit), true);
        assertEq(lPool.supportsInterface(erc7540Redeem), true);

        assertEq(lPool.supportsInterface(unsupportedInterfaceId), false);
    }

    // --- callbacks ---
    function testSucceedingCallbacks(bytes memory depositData, bytes memory redeemData) public {
        vm.assume(depositData.length > 0);
        vm.assume(redeemData.length > 0);

        address lPool_ = deploySimplePool();
        LiquidityPool lPool = LiquidityPool(lPool_);
        SucceedingRequestReceiver receiver = new SucceedingRequestReceiver();

        centrifugeChain.updateMember(lPool.poolId(), lPool.trancheId(), address(receiver), type(uint64).max);
        centrifugeChain.updateMember(lPool.poolId(), lPool.trancheId(), self, type(uint64).max);

        uint256 amount = 100 * 10 ** 6;
        erc20.mint(self, amount);
        erc20.approve(lPool_, amount);

        // Check deposit callback
        lPool.requestDeposit(amount, address(receiver), self, depositData);

        assertEq(erc20.balanceOf(self), 0);
        assertEq(receiver.values_address("requestDeposit_operator"), self);
        assertEq(receiver.values_address("requestDeposit_owner"), self);
        assertEq(receiver.values_uint256("requestDeposit_requestId"), 0);
        assertEq(receiver.values_uint256("requestDeposit_assets"), amount);
        assertEq(receiver.values_bytes("requestDeposit_data"), depositData);

        assertTrue(receiver.onERC7540DepositReceived(self, self, 0, amount, depositData) == 0x6d7e2da0);

        // Claim deposit request
        // Note this is sending it to self, which is technically incorrect, it should be going to the receiver
        centrifugeChain.isExecutedCollectInvest(
            lPool.poolId(),
            lPool.trancheId(),
            bytes32(bytes20(self)),
            defaultCurrencyId,
            uint128(amount),
            uint128(amount),
            0
        );
        lPool.mint(lPool.maxMint(self), self);

        // Check redeem callback
        lPool.requestRedeem(amount, address(receiver), self, redeemData);

        TrancheToken trancheToken = TrancheToken(address(lPool.share()));
        assertEq(trancheToken.balanceOf(self), 0);
        assertEq(receiver.values_address("requestRedeem_operator"), self);
        assertEq(receiver.values_address("requestRedeem_owner"), self);
        assertEq(receiver.values_uint256("requestRedeem_requestId"), 0);
        assertEq(receiver.values_uint256("requestRedeem_shares"), amount);
        assertEq(receiver.values_bytes("requestRedeem_data"), redeemData);

        assertTrue(receiver.onERC7540RedeemReceived(self, self, 0, amount, redeemData) == 0x01a2e97e);
    }

    // function testSucceedingCallbacksNotCalledWithEmptyData() public {
    //     address lPool_ = deploySimplePool();
    //     LiquidityPool lPool = LiquidityPool(lPool_);
    //     SucceedingRequestReceiver receiver = new SucceedingRequestReceiver();

    //     centrifugeChain.updateMember(lPool.poolId(), lPool.trancheId(), address(receiver), type(uint64).max);
    //     centrifugeChain.updateMember(lPool.poolId(), lPool.trancheId(), self, type(uint64).max);

    //     uint256 amount = 100 * 10 ** 6;
    //     erc20.mint(self, amount);
    //     erc20.approve(lPool_, amount);

    //     // Check deposit callback
    //     lPool.requestDeposit(amount, address(receiver), self, "");

    //     assertEq(receiver.values_address("requestDeposit_operator"), address(0));
    //     assertEq(receiver.values_address("requestDeposit_owner"), address(0));
    //     assertEq(receiver.values_uint256("requestDeposit_requestId"), 0);
    //     assertEq(receiver.values_uint256("requestDeposit_assets"), 0);
    //     assertEq(receiver.values_bytes("requestDeposit_data"), "");

    //     // Claim deposit request
    //     // Note this is sending it to self, which is technically incorrect, it should be going to the receiver
    //     centrifugeChain.isExecutedCollectInvest(
    //         lPool.poolId(),
    //         lPool.trancheId(),
    //         bytes32(bytes20(self)),
    //         defaultCurrencyId,
    //         uint128(amount),
    //         uint128(amount),
    //         0
    //     );
    //     lPool.mint(lPool.maxMint(self), self);

    //     // Check redeem callback
    //     lPool.requestRedeem(amount, address(receiver), self, "");

    //     TrancheToken trancheToken = TrancheToken(address(lPool.share()));
    //     assertEq(trancheToken.balanceOf(self), 0);
    //     assertEq(receiver.values_address("requestRedeem_operator"), address(0));
    //     assertEq(receiver.values_address("requestRedeem_owner"), address(0));
    //     assertEq(receiver.values_uint256("requestRedeem_requestId"), 0);
    //     assertEq(receiver.values_uint256("requestRedeem_shares"), 0);
    //     assertEq(receiver.values_bytes("requestRedeem_data"), "");
    // }

    function testFailingCallbacks(bytes memory depositData, bytes memory redeemData) public {
        address lPool_ = deploySimplePool();
        LiquidityPool lPool = LiquidityPool(lPool_);
        FailingRequestReceiver receiver = new FailingRequestReceiver();

        centrifugeChain.updateMember(lPool.poolId(), lPool.trancheId(), address(receiver), type(uint64).max);
        centrifugeChain.updateMember(lPool.poolId(), lPool.trancheId(), self, type(uint64).max);

        uint256 amount = 100 * 10 ** 6;
        erc20.mint(self, amount);
        erc20.approve(lPool_, amount);

        // Check deposit callback
        vm.expectRevert(bytes("LiquidityPool/receiver-failed"));
        lPool.requestDeposit(amount, address(receiver), self, depositData);

        assertEq(erc20.balanceOf(self), amount);
        assertEq(receiver.values_address("requestDeposit_operator"), self);
        assertEq(receiver.values_address("requestDeposit_owner"), self);
        assertEq(receiver.values_uint256("requestDeposit_requestId"), 0);
        assertEq(receiver.values_uint256("requestDeposit_assets"), amount);
        assertEq(receiver.values_bytes("requestDeposit_data"), depositData);

        // Re-submit and claim deposit request
        lPool.requestDeposit(amount, self, self, depositData);
        centrifugeChain.isExecutedCollectInvest(
            lPool.poolId(),
            lPool.trancheId(),
            bytes32(bytes20(self)),
            defaultCurrencyId,
            uint128(amount),
            uint128(amount),
            0
        );
        lPool.mint(lPool.maxMint(self), self);

        // Check redeem callback
        vm.expectRevert(bytes("LiquidityPool/receiver-failed"));
        lPool.requestRedeem(amount, address(receiver), self, redeemData);

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
        address lPool_ = deploySimplePool();
        LiquidityPool lPool = LiquidityPool(lPool_);

        vm.expectRevert(bytes(""));
        lPool.previewDeposit(amount);

        vm.expectRevert(bytes(""));
        lPool.previewRedeem(amount);

        vm.expectRevert(bytes(""));
        lPool.previewMint(amount);

        vm.expectRevert(bytes(""));
        lPool.previewWithdraw(amount);
    }
}
