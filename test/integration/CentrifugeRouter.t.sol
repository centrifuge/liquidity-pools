// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import "test/BaseTest.sol";
import "src/interfaces/IERC7575.sol";
import "src/interfaces/IERC7540.sol";
import "src/interfaces/IERC20.sol";
import {GatewayV2} from "src/gateway/GatewayV2.sol";
import {CentrifugeRouter} from "src/CentrifugeRouter.sol";

contract CentrifugeRouterTest is BaseTest {
    GatewayV2 gatewayV2;
    uint256 constant GATEWAY_TOPUP_VALUE = 1 ether;

    function setUp() public override {
        super.setUp();
        gatewayV2 =
            new GatewayV2(address(root), address(investmentManager), address(poolManager), address(mockedGasService));
        gatewayV2.file("routers", testRouters);
        gatewayV2.rely(address(investmentManager));
        gateway.rely(address(root));
        payable(address(gatewayV2)).transfer(GATEWAY_TOPUP_VALUE);

        root.relyContract(address(investmentManager), address(this));
        investmentManager.file("gateway", address(gatewayV2));
        centrifugeRouter = new CentrifugeRouter(address(poolManager), address(gatewayV2));
        root.endorse(address(centrifugeRouter));
    }

    uint256 constant GAS_BUFFER = 10 gwei;
    /// @dev Payload is not taken into account during gas estimation
    bytes constant PAYLOAD_FOR_GAS_ESTIMATION = "irrelevant_value";

    function testCFGRouterDeposit(uint256 amount) public {
        // If lower than 4 or odd, rounding down can lead to not receiving any tokens
        amount = uint128(bound(amount, 4, MAX_UINT128));
        vm.assume(amount % 2 == 0);

        address vault_ = deploySimpleVault();
        ERC7540Vault vault = ERC7540Vault(vault_);
        vm.label(vault_, "vault");

        erc20.mint(self, amount);

        vm.expectRevert(bytes("Gateway/cannot-topup-with-nothing"));
        centrifugeRouter.requestDeposit(vault_, amount, 0);

        vm.expectRevert(bytes("InvestmentManager/owner-is-restricted")); // fail: receiver not member
        centrifugeRouter.requestDeposit{value: 1 wei}(vault_, amount, 1 wei);
        centrifugeChain.updateMember(vault.poolId(), vault.trancheId(), self, type(uint64).max); // add user as member

        uint256 gas = estimateGas() + GAS_BUFFER;

        vm.expectRevert(bytes("SafeTransferLib/safe-transfer-from-failed")); // fail: no allowance
        centrifugeRouter.requestDeposit{value: gas}(vault_, amount, gas);

        erc20.approve(vault_, amount); // grant approval to cfg router
        centrifugeRouter.requestDeposit{value: gas}(vault_, amount, gas);

        assertEq(address(gatewayV2).balance, GATEWAY_TOPUP_VALUE + GAS_BUFFER);

        for (uint8 i; i < testRouters.length; i++) {
            MockRouter router = MockRouter(testRouters[i]);
            uint256[] memory payCalls = router.callsWithValue("pay");
            assertEq(payCalls.length, 1);
            assertEq(
                payCalls[0],
                router.estimate(PAYLOAD_FOR_GAS_ESTIMATION, mockedGasService.estimate(PAYLOAD_FOR_GAS_ESTIMATION))
            );
        }

        // trigger - deposit order fulfillment
        uint128 assetId = poolManager.assetToId(address(erc20));
        (uint128 trancheTokensPayout) = fulfillDepositRequest(vault, assetId, amount);

        assertEq(vault.maxMint(self), trancheTokensPayout);
        assertEq(vault.maxDeposit(self), amount);
        TrancheTokenLike trancheToken = TrancheTokenLike(address(vault.share()));
        assertEq(trancheToken.balanceOf(address(escrow)), trancheTokensPayout);

        centrifugeRouter.claimDeposit(vault_, self);
        assertApproxEqAbs(trancheToken.balanceOf(self), trancheTokensPayout, 1);
        assertApproxEqAbs(trancheToken.balanceOf(self), trancheTokensPayout, 1);
        assertApproxEqAbs(trancheToken.balanceOf(address(escrow)), 0, 1);
        assertApproxEqAbs(erc20.balanceOf(address(escrow)), amount, 1);
    }

    function testRouterAsyncDeposit(uint256 amount) public {
        amount = uint128(bound(amount, 4, MAX_UINT128));
        vm.assume(amount % 2 == 0);

        address vault_ = deploySimpleVault();
        ERC7540Vault vault = ERC7540Vault(vault_);
        vm.label(vault_, "vault");

        erc20.mint(self, amount);
        erc20.approve(address(centrifugeRouter), amount);
        centrifugeChain.updateMember(vault.poolId(), vault.trancheId(), self, type(uint64).max);
        centrifugeRouter.lockDepositRequest(vault_, amount);

        // Any address should be able to call executeLockedDepositRequest for an investor
        address randomAddress = address(0x123);
        vm.label(randomAddress, "randomAddress");
        vm.startPrank(randomAddress);
        centrifugeRouter.approveVault(vault_);
        centrifugeRouter.executeLockedDepositRequest(vault_, address(this));
        vm.stopPrank();

        uint128 assetId = poolManager.assetToId(address(erc20));
        (uint128 trancheTokensPayout) = fulfillDepositRequest(vault, assetId, amount);

        assertEq(vault.maxMint(self), trancheTokensPayout);
        assertEq(vault.maxDeposit(self), amount);
        TrancheTokenLike trancheToken = TrancheTokenLike(address(vault.share()));
        assertEq(trancheToken.balanceOf(address(escrow)), trancheTokensPayout);

        // Any address should be able to call claimDeposit for an investor
        vm.prank(randomUser);
        centrifugeRouter.claimDeposit(vault_, self);
        assertApproxEqAbs(trancheToken.balanceOf(self), trancheTokensPayout, 1);
        assertApproxEqAbs(trancheToken.balanceOf(address(escrow)), 0, 1);
        assertApproxEqAbs(erc20.balanceOf(address(escrow)), amount, 1);
    }

    function testRouterRedeem(uint256 amount) public {
        amount = uint128(bound(amount, 4, MAX_UINT128));
        vm.assume(amount % 2 == 0);

        // deposit
        address vault_ = deploySimpleVault();
        ERC7540Vault vault = ERC7540Vault(vault_);
        vm.label(vault_, "vault");
        erc20.mint(self, amount);
        erc20.approve(vault_, amount);
        centrifugeChain.updateMember(vault.poolId(), vault.trancheId(), self, type(uint64).max);
        uint256 fuel = estimateGas();
        centrifugeRouter.requestDeposit{value: fuel}(vault_, amount, fuel);
        uint128 assetId = poolManager.assetToId(address(erc20));
        (uint128 trancheTokensPayout) = fulfillDepositRequest(vault, assetId, amount);
        TrancheTokenLike trancheToken = TrancheTokenLike(address(vault.share()));
        centrifugeRouter.claimDeposit(vault_, self);

        // redeem
        trancheToken.approve(address(centrifugeRouter), trancheTokensPayout);
        centrifugeRouter.requestRedeem(vault_, trancheTokensPayout);
        (uint128 assetPayout) = fulfillRedeemRequest(vault, assetId, trancheTokensPayout);
        assertApproxEqAbs(trancheToken.balanceOf(self), 0, 1);
        assertApproxEqAbs(trancheToken.balanceOf(address(escrow)), 0, 1);
        assertApproxEqAbs(erc20.balanceOf(address(escrow)), assetPayout, 1);
        assertApproxEqAbs(erc20.balanceOf(self), 0, 1);
        centrifugeRouter.claimRedeem(vault_, self);
        assertApproxEqAbs(erc20.balanceOf(address(escrow)), 0, 1);
        assertApproxEqAbs(erc20.balanceOf(self), assetPayout, 1);
    }

    function testRouterDepositIntoMultipleVaults(uint256 amount1, uint256 amount2) public {
        amount1 = uint128(bound(amount1, 4, MAX_UINT128));
        vm.assume(amount1 % 2 == 0);
        amount2 = uint128(bound(amount2, 4, MAX_UINT128));
        vm.assume(amount2 % 2 == 0);

        uint256 fuel = estimateGas();
        (ERC20 erc20X, ERC20 erc20Y, ERC7540Vault vault1, ERC7540Vault vault2) = setUpMultipleVaults(amount1, amount2);
        centrifugeRouter.requestDeposit{value: fuel}(address(vault1), amount1, fuel);
        centrifugeRouter.requestDeposit{value: fuel}(address(vault2), amount2, fuel);

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

        centrifugeRouter.claimDeposit(address(vault1), self);
        centrifugeRouter.claimDeposit(address(vault2), self);
        assertApproxEqAbs(trancheToken1.balanceOf(self), trancheTokensPayout1, 1);
        assertApproxEqAbs(trancheToken2.balanceOf(self), trancheTokensPayout2, 1);
        assertApproxEqAbs(trancheToken1.balanceOf(address(escrow)), 0, 1);
        assertApproxEqAbs(trancheToken2.balanceOf(address(escrow)), 0, 1);
        assertApproxEqAbs(erc20X.balanceOf(address(escrow)), amount1, 1);
        assertApproxEqAbs(erc20Y.balanceOf(address(escrow)), amount2, 1);
    }

    function testRouterRedeemFromMultipleVaults(uint256 amount1, uint256 amount2) public {
        amount1 = uint128(bound(amount1, 4, MAX_UINT128));
        vm.assume(amount1 % 2 == 0);
        amount2 = uint128(bound(amount2, 4, MAX_UINT128));
        vm.assume(amount2 % 2 == 0);

        uint256 fuel = estimateGas();
        // deposit
        (ERC20 erc20X, ERC20 erc20Y, ERC7540Vault vault1, ERC7540Vault vault2) = setUpMultipleVaults(amount1, amount2);
        centrifugeRouter.requestDeposit{value: fuel}(address(vault1), amount1, fuel);
        centrifugeRouter.requestDeposit{value: fuel}(address(vault2), amount2, fuel);
        uint128 assetId1 = poolManager.assetToId(address(erc20X));
        uint128 assetId2 = poolManager.assetToId(address(erc20Y));
        (uint128 trancheTokensPayout1) = fulfillDepositRequest(vault1, assetId1, amount1);
        (uint128 trancheTokensPayout2) = fulfillDepositRequest(vault2, assetId2, amount2);
        TrancheTokenLike trancheToken1 = TrancheTokenLike(address(vault1.share()));
        TrancheTokenLike trancheToken2 = TrancheTokenLike(address(vault2.share()));
        centrifugeRouter.claimDeposit(address(vault1), self);
        centrifugeRouter.claimDeposit(address(vault2), self);

        // redeem
        trancheToken1.approve(address(centrifugeRouter), trancheTokensPayout1);
        trancheToken2.approve(address(centrifugeRouter), trancheTokensPayout2);
        centrifugeRouter.requestRedeem(address(vault1), trancheTokensPayout1);
        centrifugeRouter.requestRedeem(address(vault2), trancheTokensPayout2);
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
        centrifugeRouter.claimRedeem(address(vault1), self);
        centrifugeRouter.claimRedeem(address(vault2), self);
        assertApproxEqAbs(erc20X.balanceOf(address(escrow)), 0, 1);
        assertApproxEqAbs(erc20Y.balanceOf(address(escrow)), 0, 1);
        assertApproxEqAbs(erc20X.balanceOf(self), assetPayout1, 1);
        assertApproxEqAbs(erc20Y.balanceOf(self), assetPayout2, 1);
    }

    function testMulticallingApproveVaultAndExecuteLockedDepositRequest(uint256 amount) public {
        amount = uint128(bound(amount, 4, MAX_UINT128));
        vm.assume(amount % 2 == 0);

        address vault_ = deploySimpleVault();
        ERC7540Vault vault = ERC7540Vault(vault_);
        vm.label(vault_, "vault");

        erc20.mint(self, amount);
        erc20.approve(address(centrifugeRouter), amount);
        centrifugeChain.updateMember(vault.poolId(), vault.trancheId(), self, type(uint64).max);
        centrifugeRouter.lockDepositRequest(vault_, amount);

        // multicall
        bytes[] memory calls = new bytes[](2);
        calls[0] = abi.encodeWithSelector(centrifugeRouter.approveVault.selector, vault_);
        calls[1] = abi.encodeWithSelector(centrifugeRouter.executeLockedDepositRequest.selector, vault_, self);
        centrifugeRouter.multicall(calls);

        uint128 assetId = poolManager.assetToId(address(erc20));
        (uint128 trancheTokensPayout) = fulfillDepositRequest(vault, assetId, amount);

        assertEq(vault.maxMint(self), trancheTokensPayout);
        assertEq(vault.maxDeposit(self), amount);
        TrancheTokenLike trancheToken = TrancheTokenLike(address(vault.share()));
        assertEq(trancheToken.balanceOf(address(escrow)), trancheTokensPayout);
    }

    function testMulticallingDepositClaimAndRequestRedeem(uint256 amount) public {
        amount = uint128(bound(amount, 4, MAX_UINT128));
        vm.assume(amount % 2 == 0);

        // deposit
        address vault_ = deploySimpleVault();
        ERC7540Vault vault = ERC7540Vault(vault_);
        vm.label(vault_, "vault");
        erc20.mint(self, amount);
        erc20.approve(vault_, amount);
        centrifugeChain.updateMember(vault.poolId(), vault.trancheId(), self, type(uint64).max);
        uint256 fuel = estimateGas();
        centrifugeRouter.requestDeposit{value: fuel}(vault_, amount, fuel);
        uint128 assetId = poolManager.assetToId(address(erc20));
        (uint128 trancheTokensPayout) = fulfillDepositRequest(vault, assetId, amount);
        TrancheTokenLike trancheToken = TrancheTokenLike(address(vault.share()));
        trancheToken.approve(address(centrifugeRouter), trancheTokensPayout);

        // multicall
        bytes[] memory calls = new bytes[](2);
        calls[0] = abi.encodeWithSelector(centrifugeRouter.claimDeposit.selector, vault_, self);
        calls[1] = abi.encodeWithSelector(centrifugeRouter.requestRedeem.selector, vault_, trancheTokensPayout);
        centrifugeRouter.multicall(calls);

        (uint128 assetPayout) = fulfillRedeemRequest(vault, assetId, trancheTokensPayout);
        assertApproxEqAbs(trancheToken.balanceOf(self), 0, 1);
        assertApproxEqAbs(trancheToken.balanceOf(address(escrow)), 0, 1);
        assertApproxEqAbs(erc20.balanceOf(address(escrow)), assetPayout, 1);
        assertApproxEqAbs(erc20.balanceOf(self), 0, 1);
    }

    function testMulticallingDepositIntoMultipleVaults(uint256 amount1, uint256 amount2) public {
        amount1 = uint128(bound(amount1, 4, MAX_UINT128));
        vm.assume(amount1 % 2 == 0);
        amount2 = uint128(bound(amount2, 4, MAX_UINT128));
        vm.assume(amount2 % 2 == 0);

        (ERC20 erc20X, ERC20 erc20Y, ERC7540Vault vault1, ERC7540Vault vault2) = setUpMultipleVaults(amount1, amount2);

        uint256 fuel = estimateGas();
        bytes[] memory calls = new bytes[](2);
        calls[0] = abi.encodeWithSelector(centrifugeRouter.requestDeposit.selector, vault1, amount1, fuel);
        calls[1] = abi.encodeWithSelector(centrifugeRouter.requestDeposit.selector, vault2, amount2, fuel);
        // TODO Figure out why does this work... There will be 2 calls on requestDeposit so how come it works like that?
        // It will send once the estimated gas to the gateway and
        // when it will try to request second deposit there should be any funds :S
        centrifugeRouter.multicall{value: fuel * calls.length}(calls);

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

    function setUpMultipleVaults(uint256 amount1, uint256 amount2)
        public
        returns (ERC20 erc20X, ERC20 erc20Y, ERC7540Vault vault1, ERC7540Vault vault2)
    {
        erc20X = _newErc20("X's Dollar", "USDX", 6);
        erc20Y = _newErc20("Y's Dollar", "USDY", 6);
        vm.label(address(erc20X), "erc20X");
        vm.label(address(erc20Y), "erc20Y");
        address vault1_ =
            deployVault(5, 6, defaultRestrictionSet, "name1", "symbol1", bytes16(bytes("1")), 1, address(erc20X));
        address vault2_ =
            deployVault(4, 6, defaultRestrictionSet, "name2", "symbol2", bytes16(bytes("2")), 2, address(erc20Y));
        vault1 = ERC7540Vault(vault1_);
        vault2 = ERC7540Vault(vault2_);
        vm.label(vault1_, "vault1");
        vm.label(vault2_, "vault2");

        erc20X.mint(self, amount1);
        erc20Y.mint(self, amount2);

        erc20X.approve(address(vault1_), amount1);
        erc20Y.approve(address(vault2_), amount2);

        centrifugeChain.updateMember(vault1.poolId(), vault1.trancheId(), self, type(uint64).max);
        centrifugeChain.updateMember(vault2.poolId(), vault2.trancheId(), self, type(uint64).max);
    }

    function estimateGas() internal view returns (uint256 total) {
        (, total) = gatewayV2.estimate(PAYLOAD_FOR_GAS_ESTIMATION);
    }
}
