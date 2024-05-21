// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.18;

import {MockCentrifugeChain} from "test/mocks/MockCentrifugeChain.sol";
import {IERC7540} from "src/interfaces/IERC7540.sol";
import {BaseHandler} from "test/invariant/handlers/BaseHandler.sol";
import {MathLib} from "src/libraries/MathLib.sol";

import "forge-std/Test.sol";

interface ERC20Like {
    function mint(address user, uint256 amount) external;
    function approve(address spender, uint256 value) external returns (bool);
    function balanceOf(address user) external view returns (uint256);
}

interface VaultLike is IERC7540 {
    function share() external view returns (address);
    function manager() external view returns (address);
}

contract InvestorHandler is BaseHandler {
    using MathLib for uint256;
    using MathLib for uint128;

    uint64 poolId;
    bytes16 trancheId;
    uint128 assetId;

    ERC20Like immutable erc20;
    ERC20Like immutable trancheToken;
    VaultLike immutable vault;
    MockCentrifugeChain immutable centrifugeChain;
    address immutable escrow;
    address immutable investmentManager;

    constructor(
        uint64 poolId_,
        bytes16 trancheId_,
        uint128 assetId_,
        address _vault,
        address mockCentrifugeChain_,
        address erc20_,
        address escrow_,
        address state_
    ) BaseHandler(state_) {
        poolId = poolId_;
        trancheId = trancheId_;
        assetId = assetId_;

        vault = VaultLike(_vault);
        centrifugeChain = MockCentrifugeChain(mockCentrifugeChain_);
        erc20 = ERC20Like(erc20_);
        trancheToken = ERC20Like(vault.share());
        escrow = escrow_;
        investmentManager = vault.manager();
    }

    // --- Investments ---
    function requestDeposit(uint256 investorSeed, uint128 amount) public useRandomInvestor(investorSeed) {
        // Don't allow total outstanding deposit requests > type(uint128).max
        uint256 amount_ = bound(
            amount,
            0,
            uint128(
                type(uint128).max - getVar(currentInvestor, "totalDepositRequested")
                    + getVar(currentInvestor, "totalCurrencyPaidOutOnInvest")
            )
        );
        if (amount == 0) return;

        vm.stopPrank();
        erc20.mint(currentInvestor, amount_);
        vm.startPrank(currentInvestor);

        erc20.approve(address(vault), amount_);

        // TODO: we should also set up tests where currentInvestor != operator
        vault.requestDeposit(amount_, currentInvestor, currentInvestor);

        increaseVar(currentInvestor, "totalDepositRequested", amount);
    }

    function deposit(uint256 investorSeed, uint128 amount) public useRandomInvestor(investorSeed) {
        uint256 amount_ = bound(amount, 0, vault.maxDeposit(currentInvestor));
        if (amount_ == 0) return;

        vault.deposit(amount_, currentInvestor);
    }

    function mint(uint256 investorSeed, uint128 amount) public useRandomInvestor(investorSeed) {
        uint256 amount_ = bound(amount, 0, vault.maxMint(currentInvestor));
        if (amount_ == 0) return;

        vault.mint(amount_, currentInvestor);
    }

    // --- Redemptions ---
    function requestRedeem(uint256 investorSeed, uint128 amount) public useRandomInvestor(investorSeed) {
        uint256 amount_ = bound(
            amount,
            0,
            _min(
                // Don't allow total outstanding redeem requests > type(uint128).max
                uint128(
                    type(uint128).max - getVar(currentInvestor, "totalRedeemRequested")
                        + getVar(currentInvestor, "totalTrancheTokensPaidOutOnRedeem")
                ),
                // Cannot redeem more than current balance of TT
                trancheToken.balanceOf(currentInvestor)
            )
        );
        if (amount_ == 0) return;

        vault.requestRedeem(amount_, currentInvestor, currentInvestor);

        increaseVar(currentInvestor, "totalRedeemRequested", amount_);
    }

    function redeem(uint256 investorSeed, uint128 amount) public useRandomInvestor(investorSeed) {
        uint256 amount_ = bound(amount, 0, vault.maxRedeem(currentInvestor));
        if (amount_ == 0) return;

        uint256 preBalance = erc20.balanceOf(currentInvestor);
        vault.redeem(amount_, currentInvestor, currentInvestor);
        uint256 postBalance = erc20.balanceOf(currentInvestor);
        increaseVar(currentInvestor, "totalCurrencyReceived", postBalance - preBalance);
    }

    function withdraw(uint256 investorSeed, uint128 amount) public useRandomInvestor(investorSeed) {
        uint256 amount_ = bound(amount, 0, vault.maxWithdraw(currentInvestor));
        if (amount_ == 0) return;

        uint256 preBalance = erc20.balanceOf(currentInvestor);
        vault.withdraw(amount_, currentInvestor, currentInvestor);
        uint256 postBalance = erc20.balanceOf(currentInvestor);
        increaseVar(currentInvestor, "totalCurrencyReceived", postBalance - preBalance);
    }
}
