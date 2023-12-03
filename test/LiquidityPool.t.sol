// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import "./TestSetup.t.sol";
import {IERC7540Deposit, IERC7540Redeem} from "src/interfaces/IERC7540.sol";
import {SucceedingRequestReceiver} from "test/mock/SucceedingRequestReceiver.sol";
import {FailingRequestReceiver} from "test/mock/FailingRequestReceiver.sol";

contract LiquidityPoolTest is TestSetup {
    // Deployment
    function testDeployment(
        uint64 poolId,
        string memory tokenName,
        string memory tokenSymbol,
        bytes16 trancheId,
        uint128 currencyId
    ) public {
        vm.assume(currencyId > 0);

        address lPool_ = deployLiquidityPool(poolId, erc20.decimals(), tokenName, tokenSymbol, trancheId, currencyId);
        LiquidityPool lPool = LiquidityPool(lPool_);

        // values set correctly
        assertEq(address(lPool.manager()), address(investmentManager));
        assertEq(lPool.asset(), address(erc20));
        assertEq(lPool.poolId(), poolId);
        assertEq(lPool.trancheId(), trancheId);
        address token = poolManager.getTrancheToken(poolId, trancheId);
        assertEq(address(lPool.share()), token);
        assertEq(_bytes128ToString(_stringToBytes128(tokenName)), _bytes128ToString(_stringToBytes128(lPool.name())));
        assertEq(_bytes32ToString(_stringToBytes32(tokenSymbol)), _bytes32ToString(_stringToBytes32(lPool.symbol())));

        // permissions set correctly
        assertEq(lPool.wards(address(root)), 1);
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
        lPool.requestDeposit(amount, self);

        TrancheTokenLike trancheToken = TrancheTokenLike(address(lPool.share()));
        centrifugeChain.updateMember(lPool.poolId(), lPool.trancheId(), self, type(uint64).max);
        root.relyContract(address(trancheToken), self);
        trancheToken.mint(address(this), amount);
        vm.expectRevert(bytes("MathLib/uint128-overflow"));
        lPool.requestRedeem(amount, address(this), address(this));

        vm.expectRevert(bytes("MathLib/uint128-overflow"));
        lPool.decreaseDepositRequest(amount);

        vm.expectRevert(bytes("MathLib/uint128-overflow"));
        lPool.decreaseRedeemRequest(amount);
    }

    // --- erc165 checks ---
    function testERC165Support(bytes4 unsupportedInterfaceId) public {
        bytes4 erc165 = 0x01ffc9a7;
        bytes4 erc7540Deposit = 0x1683f250;
        bytes4 erc7540Redeem = 0x0899cb0b;

        vm.assume(unsupportedInterfaceId != erc165 && unsupportedInterfaceId != erc7540Deposit && unsupportedInterfaceId != erc7540Redeem);

        address lPool_ = deploySimplePool();
        LiquidityPool lPool = LiquidityPool(lPool_);

        assertEq(type(IERC7540Deposit).interfaceId, erc7540Deposit);
        assertEq(type(IERC7540Redeem).interfaceId, erc7540Redeem);

        assertEq(lPool.supportsInterface(erc165), true);
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

        uint256 amount = 100*10**6;
        erc20.mint(self, amount);
        erc20.approve(lPool_, amount);

        // Check deposit callback
        lPool.requestDeposit(amount, address(receiver), self, depositData);

        assertEq(erc20.balanceOf(self), 0);
        assertEq(receiver.values_address("requestDeposit_operator"), self);
        assertEq(receiver.values_address("requestDeposit_owner"), self);
        assertEq(receiver.values_uint256("requestDeposit_requestId"), 0);
        assertEq(receiver.values_bytes("requestDeposit_data"), depositData);

        assertTrue(receiver.onERC7540DepositReceived(self, self, 0, depositData) == 0xe74d2a41);

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

        assertEq(lPool.balanceOf(self), 0);
        assertEq(receiver.values_address("requestRedeem_operator"), self);
        assertEq(receiver.values_address("requestRedeem_owner"), self);
        assertEq(receiver.values_uint256("requestRedeem_requestId"), 0);
        assertEq(receiver.values_bytes("requestRedeem_data"), redeemData);

        assertTrue(receiver.onERC7540RedeemReceived(self, self, 0, redeemData) == 0x0102fde4);
    }

    function testFailingCallbacks(bytes memory depositData, bytes memory redeemData) public {
        address lPool_ = deploySimplePool();
        LiquidityPool lPool = LiquidityPool(lPool_);
        FailingRequestReceiver receiver = new FailingRequestReceiver();

        centrifugeChain.updateMember(lPool.poolId(), lPool.trancheId(), address(receiver), type(uint64).max);
        centrifugeChain.updateMember(lPool.poolId(), lPool.trancheId(), self, type(uint64).max);

        uint256 amount = 100*10**6;
        erc20.mint(self, amount);
        erc20.approve(lPool_, amount);

        // Check deposit callback
        vm.expectRevert(bytes("LiquidityPool/receiver-failed"));
        lPool.requestDeposit(amount, address(receiver), self, depositData);

        assertEq(erc20.balanceOf(self), amount);
        assertEq(receiver.values_address("requestDeposit_operator"), self);
        assertEq(receiver.values_address("requestDeposit_owner"), self);
        assertEq(receiver.values_uint256("requestDeposit_requestId"), 0);
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

    function testTransferFrom(uint256 amount, uint256 transferAmount) public {
        transferAmount = uint128(bound(transferAmount, 2, MAX_UINT128));
        amount = uint128(bound(amount, 2, MAX_UINT128));
        vm.assume(transferAmount <= amount);

        address lPool_ = deploySimplePool();

        deposit(lPool_, investor, amount); // deposit funds first // deposit funds first
        LiquidityPool lPool = LiquidityPool(lPool_);
        centrifugeChain.updateMember(lPool.poolId(), lPool.trancheId(), self, type(uint64).max); // put self on memberlist to be able to receive tranche tokens
        centrifugeChain.updateTrancheTokenPrice(lPool.poolId(), lPool.trancheId(), defaultCurrencyId, defaultPrice, uint64(block.timestamp));

        TrancheToken trancheToken = TrancheToken(address(lPool.share()));
        assertEq(trancheToken.isTrustedForwarder(lPool_), true); // Lpool is trusted forwarder on token

        uint256 initBalance = lPool.balanceOf(investor);

        // replacing msg sender only possible for trusted forwarder
        assertEq(trancheToken.isTrustedForwarder(self), false); // self is not trusted forwarder on token
        (bool success,) = address(trancheToken).call(
            abi.encodeWithSelector(
                bytes4(keccak256(bytes("transferFrom(address,address,uint256)"))),
                investor,
                self,
                transferAmount,
                investor
            )
        );
        assertEq(success, false);

        // remove LiquidityPool as trusted forwarder
        root.relyContract(address(trancheToken), self);
        trancheToken.removeTrustedForwarder(lPool_);
        assertEq(trancheToken.isTrustedForwarder(lPool_), false); // adding trusted forwarder works

        vm.expectRevert(bytes("ERC20/insufficient-allowance"));
        vm.prank(investor);
        lPool.transferFrom(investor, self, transferAmount);

        // add liquidityPool back as trusted forwarder
        trancheToken.addTrustedForwarder(lPool_);

        vm.prank(investor);
        lPool.transferFrom(investor, self, transferAmount);
        assertEq(lPool.balanceOf(investor), (initBalance - transferAmount));
        assertEq(lPool.balanceOf(self), transferAmount);
    }

    function testApprove(uint256 amount, uint256 approvalAmount) public {
        approvalAmount = uint128(bound(approvalAmount, 2, MAX_UINT128 - 1));
        amount = uint128(bound(amount, approvalAmount + 1, MAX_UINT128)); // amount > approvalAmount

        address receiver = makeAddr("receiver");
        address lPool_ = deploySimplePool();
        LiquidityPool lPool = LiquidityPool(lPool_);
        centrifugeChain.updateTrancheTokenPrice(lPool.poolId(), lPool.trancheId(), defaultCurrencyId, defaultPrice, uint64(block.timestamp));

        TrancheToken trancheToken = TrancheToken(address(lPool.share()));
        assertTrue(trancheToken.isTrustedForwarder(lPool_)); // Lpool is not trusted forwarder on token

        // replacing msg sender only possible for trusted forwarder
        assertEq(trancheToken.isTrustedForwarder(self), false); // Lpool is not trusted forwarder on token
        (bool success,) = address(trancheToken).call(
            abi.encodeWithSelector(
                bytes4(keccak256(bytes("approve(address,uint256)"))), receiver, approvalAmount, investor
            )
        );

        assertEq(success, true);
        assertEq(lPool.allowance(self, receiver), approvalAmount);
        assertEq(lPool.allowance(investor, receiver), 0);

        // remove LiquidityPool as trusted forwarder
        root.relyContract(address(trancheToken), self);
        trancheToken.removeTrustedForwarder(lPool_);
        assertEq(trancheToken.isTrustedForwarder(lPool_), false); // adding trusted forwarder works

        vm.prank(investor);
        lPool.approve(receiver, approvalAmount);
        assertEq(lPool.allowance(lPool_, receiver), approvalAmount);
        assertEq(lPool.allowance(investor, receiver), 0);

        // add liquidityPool back as trusted forwarder
        trancheToken.addTrustedForwarder(lPool_);

        vm.prank(investor);
        lPool.approve(receiver, approvalAmount);
        assertEq(lPool.allowance(investor, receiver), approvalAmount);
    }

    function testTransfer(uint256 transferAmount, uint256 amount) public {
        transferAmount = uint128(bound(transferAmount, 2, MAX_UINT128));
        amount = uint128(bound(amount, 2, MAX_UINT128));
        vm.assume(transferAmount <= amount);

        address lPool_ = deploySimplePool();

        deposit(lPool_, investor, amount); // deposit funds first // deposit funds first
        LiquidityPool lPool = LiquidityPool(lPool_);
        centrifugeChain.updateMember(lPool.poolId(), lPool.trancheId(), self, type(uint64).max); // put self on memberlist to be able to receive tranche tokens

        TrancheToken trancheToken = TrancheToken(address(lPool.share()));
        assertTrue(trancheToken.isTrustedForwarder(lPool_)); // Lpool is not trusted forwarder on token

        uint256 initBalance = lPool.balanceOf(investor);
        // replacing msg sender only possible for trusted forwarder
        assertEq(trancheToken.isTrustedForwarder(self), false); // Lpool is not trusted forwarder on token
        (bool success,) = address(trancheToken).call(
            abi.encodeWithSelector(
                bytes4(keccak256(bytes("transfer(address,uint256)"))), self, transferAmount, investor
            )
        );
        assertEq(success, false);

        // remove LiquidityPool as trusted forwarder
        root.relyContract(address(trancheToken), self);
        trancheToken.removeTrustedForwarder(lPool_);
        assertEq(trancheToken.isTrustedForwarder(lPool_), false); // adding trusted forwarder works

        vm.expectRevert(bytes("ERC20/insufficient-balance"));
        vm.prank(investor);
        lPool.transfer(self, transferAmount);

        // add liquidityPool back as trusted forwarder
        trancheToken.addTrustedForwarder(lPool_);
        vm.prank(investor);
        lPool.transfer(self, transferAmount);

        assertEq(lPool.balanceOf(investor), (initBalance - transferAmount));
        assertEq(lPool.balanceOf(self), transferAmount);
    }
}
