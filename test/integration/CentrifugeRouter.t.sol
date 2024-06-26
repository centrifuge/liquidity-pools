// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import "test/BaseTest.sol";
import "src/interfaces/IERC7575.sol";
import "src/interfaces/IERC7540.sol";
import "src/interfaces/IERC20.sol";
import {CentrifugeRouter} from "src/CentrifugeRouter.sol";
import {MockERC20Wrapper} from "test/mocks/MockERC20Wrapper.sol";

contract CentrifugeRouterTest is BaseTest {
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
        router.requestDeposit(vault_, amount, self, self, 0);

        vm.expectRevert(bytes("InvestmentManager/owner-is-restricted"));
        router.requestDeposit{value: 1 wei}(vault_, amount, self, self, 1 wei);
        centrifugeChain.updateMember(vault.poolId(), vault.trancheId(), self, type(uint64).max);

        uint256 gas = estimateGas() + GAS_BUFFER;

        vm.expectRevert(bytes("SafeTransferLib/safe-transfer-from-failed"));
        router.requestDeposit{value: gas}(vault_, amount, self, self, gas);
        erc20.approve(vault_, amount);

        router.requestDeposit{value: gas}(vault_, amount, self, self, gas);

        assertEq(address(gateway).balance, GATEWAY_INITIAL_BALACE + GAS_BUFFER);
        for (uint8 i; i < testAdapters.length; i++) {
            MockAdapter adapter = MockAdapter(testAdapters[i]);
            uint256[] memory payCalls = adapter.callsWithValue("pay");
            assertEq(payCalls.length, 1);
            assertEq(
                payCalls[0],
                adapter.estimate(PAYLOAD_FOR_GAS_ESTIMATION, mockedGasService.estimate(PAYLOAD_FOR_GAS_ESTIMATION))
            );
        }

        // trigger - deposit order fulfillment
        uint128 assetId = poolManager.assetToId(address(erc20));
        (uint128 tranchesPayout) = fulfillDepositRequest(vault, assetId, amount, self);

        assertEq(vault.maxMint(self), tranchesPayout);
        assertEq(vault.maxDeposit(self), amount);
        ITranche tranche = ITranche(address(vault.share()));
        assertEq(tranche.balanceOf(address(escrow)), tranchesPayout);

        router.claimDeposit(vault_, self, self);
        assertApproxEqAbs(tranche.balanceOf(self), tranchesPayout, 1);
        assertApproxEqAbs(tranche.balanceOf(self), tranchesPayout, 1);
        assertApproxEqAbs(tranche.balanceOf(address(escrow)), 0, 1);
        assertApproxEqAbs(erc20.balanceOf(address(escrow)), amount, 1);
    }

    function testRouterAsyncDeposit(uint256 amount) public {
        amount = uint128(bound(amount, 4, MAX_UINT128));
        vm.assume(amount % 2 == 0);

        address vault_ = deploySimpleVault();
        ERC7540Vault vault = ERC7540Vault(vault_);
        vm.label(vault_, "vault");

        erc20.mint(self, amount);
        erc20.approve(address(router), amount);
        centrifugeChain.updateMember(vault.poolId(), vault.trancheId(), self, type(uint64).max);
        router.openLockDepositRequest(vault_, amount);

        // Any address should be able to call executeLockedDepositRequest for an investor
        address randomAddress = address(0x123);
        vm.label(randomAddress, "randomAddress");
        vm.startPrank(randomAddress);
        router.executeLockedDepositRequest(vault_, address(this));
        vm.stopPrank();

        uint128 assetId = poolManager.assetToId(address(erc20));
        (uint128 tranchesPayout) = fulfillDepositRequest(vault, assetId, amount, self);

        assertEq(vault.maxMint(self), tranchesPayout);
        assertEq(vault.maxDeposit(self), amount);
        ITranche tranche = ITranche(address(vault.share()));
        assertEq(tranche.balanceOf(address(escrow)), tranchesPayout);

        // Any address should be able to call claimDeposit for an investor
        vm.prank(randomUser);
        router.claimDeposit(vault_, self, self);
        assertApproxEqAbs(tranche.balanceOf(self), tranchesPayout, 1);
        assertApproxEqAbs(tranche.balanceOf(address(escrow)), 0, 1);
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
        router.requestDeposit{value: fuel}(vault_, amount, self, self, fuel);

        uint128 assetId = poolManager.assetToId(address(erc20));
        (uint128 tranchesPayout) = fulfillDepositRequest(vault, assetId, amount, self);
        ITranche tranche = ITranche(address(vault.share()));
        router.claimDeposit(vault_, self, self);

        // redeem
        tranche.approve(address(router), tranchesPayout);
        router.requestRedeem(vault_, tranchesPayout, self, self);
        (uint128 assetPayout) = fulfillRedeemRequest(vault, assetId, tranchesPayout, self);
        assertApproxEqAbs(tranche.balanceOf(self), 0, 1);
        assertApproxEqAbs(tranche.balanceOf(address(escrow)), 0, 1);
        assertApproxEqAbs(erc20.balanceOf(address(escrow)), assetPayout, 1);
        assertApproxEqAbs(erc20.balanceOf(self), 0, 1);
        router.claimRedeem(vault_, self, self);
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
        router.requestDeposit{value: fuel}(address(vault1), amount1, self, self, fuel);
        router.requestDeposit{value: fuel}(address(vault2), amount2, self, self, fuel);

        // trigger - deposit order fulfillment
        uint128 assetId1 = poolManager.assetToId(address(erc20X));
        uint128 assetId2 = poolManager.assetToId(address(erc20Y));
        (uint128 tranchesPayout1) = fulfillDepositRequest(vault1, assetId1, amount1, self);
        (uint128 tranchesPayout2) = fulfillDepositRequest(vault2, assetId2, amount2, self);

        assertEq(vault1.maxMint(self), tranchesPayout1);
        assertEq(vault2.maxMint(self), tranchesPayout2);
        assertEq(vault1.maxDeposit(self), amount1);
        assertEq(vault2.maxDeposit(self), amount2);
        ITranche tranche1 = ITranche(address(vault1.share()));
        ITranche tranche2 = ITranche(address(vault2.share()));
        assertEq(tranche1.balanceOf(address(escrow)), tranchesPayout1);
        assertEq(tranche2.balanceOf(address(escrow)), tranchesPayout2);

        router.claimDeposit(address(vault1), self, self);
        router.claimDeposit(address(vault2), self, self);
        assertApproxEqAbs(tranche1.balanceOf(self), tranchesPayout1, 1);
        assertApproxEqAbs(tranche2.balanceOf(self), tranchesPayout2, 1);
        assertApproxEqAbs(tranche1.balanceOf(address(escrow)), 0, 1);
        assertApproxEqAbs(tranche2.balanceOf(address(escrow)), 0, 1);
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
        router.requestDeposit{value: fuel}(address(vault1), amount1, self, self, fuel);
        router.requestDeposit{value: fuel}(address(vault2), amount2, self, self, fuel);

        uint128 assetId1 = poolManager.assetToId(address(erc20X));
        uint128 assetId2 = poolManager.assetToId(address(erc20Y));
        (uint128 tranchesPayout1) = fulfillDepositRequest(vault1, assetId1, amount1, self);
        (uint128 tranchesPayout2) = fulfillDepositRequest(vault2, assetId2, amount2, self);
        ITranche tranche1 = ITranche(address(vault1.share()));
        ITranche tranche2 = ITranche(address(vault2.share()));
        router.claimDeposit(address(vault1), self, self);
        router.claimDeposit(address(vault2), self, self);

        // redeem
        tranche1.approve(address(router), tranchesPayout1);
        tranche2.approve(address(router), tranchesPayout2);
        router.requestRedeem(address(vault1), tranchesPayout1, self, self);
        router.requestRedeem(address(vault2), tranchesPayout2, self, self);
        (uint128 assetPayout1) = fulfillRedeemRequest(vault1, assetId1, tranchesPayout1, self);
        (uint128 assetPayout2) = fulfillRedeemRequest(vault2, assetId2, tranchesPayout2, self);
        assertApproxEqAbs(tranche1.balanceOf(self), 0, 1);
        assertApproxEqAbs(tranche2.balanceOf(self), 0, 1);
        assertApproxEqAbs(tranche1.balanceOf(address(escrow)), 0, 1);
        assertApproxEqAbs(tranche2.balanceOf(address(escrow)), 0, 1);
        assertApproxEqAbs(erc20X.balanceOf(address(escrow)), assetPayout1, 1);
        assertApproxEqAbs(erc20Y.balanceOf(address(escrow)), assetPayout2, 1);
        assertApproxEqAbs(erc20X.balanceOf(self), 0, 1);
        assertApproxEqAbs(erc20Y.balanceOf(self), 0, 1);
        router.claimRedeem(address(vault1), self, self);
        router.claimRedeem(address(vault2), self, self);
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
        erc20.approve(address(router), amount);
        centrifugeChain.updateMember(vault.poolId(), vault.trancheId(), self, type(uint64).max);
        router.lockDepositRequest(vault_, amount, self, self);

        // multicall
        bytes[] memory calls = new bytes[](1);
        calls[0] = abi.encodeWithSelector(router.executeLockedDepositRequest.selector, vault_, self);
        router.multicall(calls);

        uint128 assetId = poolManager.assetToId(address(erc20));
        (uint128 tranchesPayout) = fulfillDepositRequest(vault, assetId, amount, self);

        assertEq(vault.maxMint(self), tranchesPayout);
        assertEq(vault.maxDeposit(self), amount);
        ITranche tranche = ITranche(address(vault.share()));
        assertEq(tranche.balanceOf(address(escrow)), tranchesPayout);
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
        router.requestDeposit{value: fuel}(vault_, amount, self, self, fuel);

        uint128 assetId = poolManager.assetToId(address(erc20));
        (uint128 tranchesPayout) = fulfillDepositRequest(vault, assetId, amount, self);
        ITranche tranche = ITranche(address(vault.share()));
        tranche.approve(address(router), tranchesPayout);

        // multicall
        bytes[] memory calls = new bytes[](2);
        calls[0] = abi.encodeWithSelector(router.claimDeposit.selector, vault_, self, self);
        calls[1] = abi.encodeWithSelector(router.requestRedeem.selector, vault_, tranchesPayout, self, self);
        router.multicall(calls);

        (uint128 assetPayout) = fulfillRedeemRequest(vault, assetId, tranchesPayout, self);
        assertApproxEqAbs(tranche.balanceOf(self), 0, 1);
        assertApproxEqAbs(tranche.balanceOf(address(escrow)), 0, 1);
        assertApproxEqAbs(erc20.balanceOf(address(escrow)), assetPayout, 1);
        assertApproxEqAbs(erc20.balanceOf(self), 0, 1);
    }

    function testMulticallingDepositIntoMultipleVaults(uint256 amount1, uint256 amount2) public {
        amount1 = uint128(bound(amount1, 4, MAX_UINT128));
        vm.assume(amount1 % 2 == 0);
        amount2 = uint128(bound(amount2, 4, MAX_UINT128));
        vm.assume(amount2 % 2 == 0);

        (ERC20 erc20X, ERC20 erc20Y, ERC7540Vault vault1, ERC7540Vault vault2) = setUpMultipleVaults(amount1, amount2);

        uint256 gas = estimateGas();
        bytes[] memory calls = new bytes[](2);
        calls[0] = abi.encodeWithSelector(router.requestDeposit.selector, vault1, amount1, self, self, gas);
        calls[1] = abi.encodeWithSelector(router.requestDeposit.selector, vault2, amount2, self, self, gas);
        router.multicall{value: gas * calls.length}(calls);

        // trigger - deposit order fulfillment
        uint128 assetId1 = poolManager.assetToId(address(erc20X));
        uint128 assetId2 = poolManager.assetToId(address(erc20Y));
        (uint128 tranchesPayout1) = fulfillDepositRequest(vault1, assetId1, amount1, self);
        (uint128 tranchesPayout2) = fulfillDepositRequest(vault2, assetId2, amount2, self);

        assertEq(vault1.maxMint(self), tranchesPayout1);
        assertEq(vault2.maxMint(self), tranchesPayout2);
        assertEq(vault1.maxDeposit(self), amount1);
        assertEq(vault2.maxDeposit(self), amount2);
        ITranche tranche1 = ITranche(address(vault1.share()));
        ITranche tranche2 = ITranche(address(vault2.share()));
        assertEq(tranche1.balanceOf(address(escrow)), tranchesPayout1);
        assertEq(tranche2.balanceOf(address(escrow)), tranchesPayout2);
    }

    function testWrapAndRequestDeposit(uint256 amount) public {
        amount = uint128(bound(amount, 4, MAX_UINT128));
        vm.assume(amount % 2 == 0);

        MockERC20Wrapper wrapper = new MockERC20Wrapper(address(erc20));
        address vault_ = deployVault(
            5, 6, restrictionManager, "name", "symbol", bytes16(bytes("1")), defaultAssetId, address(wrapper)
        );
        ERC7540Vault vault = ERC7540Vault(vault_);
        vm.label(vault_, "vault");

        address investor = makeAddr("investor");
        vm.deal(investor, 10 ether);
        centrifugeChain.updateMember(vault.poolId(), vault.trancheId(), investor, type(uint64).max);

        erc20.mint(investor, amount);
        vm.startPrank(investor);
        // TODO: use permit instead of approve, to show this is also possible
        erc20.approve(address(router), amount);

        uint256 gas = estimateGas();

        // multicall
        bytes[] memory calls = new bytes[](2);
        calls[0] = abi.encodeWithSelector(router.wrap.selector, address(wrapper), amount);
        calls[1] =
            abi.encodeWithSelector(router.requestDeposit.selector, vault_, amount, investor, address(router), gas);
        router.multicall{value: gas}(calls);

        uint128 assetId = poolManager.assetToId(address(wrapper));
        (uint128 tranchesPayout) = fulfillDepositRequest(vault, assetId, amount, investor);

        assertEq(vault.maxMint(investor), tranchesPayout);
        assertEq(vault.maxDeposit(investor), amount);
        ITranche tranche = ITranche(address(vault.share()));
        assertEq(tranche.balanceOf(address(escrow)), tranchesPayout);
    }

    function testWrapAndLockDepositRequest(uint256 amount) public {
        amount = uint128(bound(amount, 4, MAX_UINT128));
        vm.assume(amount % 2 == 0);

        MockERC20Wrapper wrapper = new MockERC20Wrapper(address(erc20));
        address vault_ = deployVault(
            5, 6, restrictionManager, "name", "symbol", bytes16(bytes("1")), defaultAssetId, address(wrapper)
        );
        ERC7540Vault vault = ERC7540Vault(vault_);
        vm.label(vault_, "vault");

        address investor = makeAddr("investor");
        centrifugeChain.updateMember(vault.poolId(), vault.trancheId(), investor, type(uint64).max);

        erc20.mint(investor, amount);
        vm.startPrank(investor);
        erc20.approve(address(router), amount);

        // multicall
        bytes[] memory calls = new bytes[](3);
        calls[0] = abi.encodeWithSelector(router.wrap.selector, address(wrapper), amount);
        calls[1] = abi.encodeWithSelector(router.lockDepositRequest.selector, vault_, amount, investor, address(router));
        calls[2] = abi.encodeWithSelector(router.executeLockedDepositRequest.selector, vault_, investor);
        router.multicall(calls);

        uint128 assetId = poolManager.assetToId(address(wrapper));
        (uint128 tranchesPayout) = fulfillDepositRequest(vault, assetId, amount, investor);

        assertEq(vault.maxMint(investor), tranchesPayout);
        assertEq(vault.maxDeposit(investor), amount);
        ITranche tranche = ITranche(address(vault.share()));
        assertEq(tranche.balanceOf(address(escrow)), tranchesPayout);
    }

    function testWrapAndUnwrap(uint256 amount) public {
        amount = uint128(bound(amount, 4, MAX_UINT128));
        vm.assume(amount % 2 == 0);

        MockERC20Wrapper wrapper = new MockERC20Wrapper(address(erc20));
        address vault_ = deployVault(
            5, 6, restrictionManager, "name", "symbol", bytes16(bytes("1")), defaultAssetId, address(wrapper)
        );
        ERC7540Vault vault = ERC7540Vault(vault_);
        vm.label(vault_, "vault");

        address investor = makeAddr("investor");
        centrifugeChain.updateMember(vault.poolId(), vault.trancheId(), investor, type(uint64).max);

        erc20.mint(investor, amount);
        vm.startPrank(investor);
        erc20.approve(address(router), amount);

        assertEq(erc20.balanceOf(investor), amount);

        // multicall
        bytes[] memory calls = new bytes[](2);
        calls[0] = abi.encodeWithSelector(router.wrap.selector, address(wrapper), amount);
        calls[1] = abi.encodeWithSelector(router.unwrap.selector, address(wrapper), amount, investor);
        router.multicall(calls);

        assertEq(erc20.balanceOf(investor), amount);
    }

    function testMultipleTopUpScenarios(uint256 amount) public {
        amount = uint128(bound(amount, 4, MAX_UINT128));
        vm.assume(amount % 2 == 0);

        address vault_ = deploySimpleVault();
        ERC7540Vault vault = ERC7540Vault(vault_);
        vm.label(vault_, "vault");

        erc20.mint(self, amount);

        centrifugeChain.updateMember(vault.poolId(), vault.trancheId(), self, type(uint64).max);
        erc20.approve(vault_, amount);

        uint256 gasLimit = estimateGas();
        uint256 lessGas = gasLimit - 1;

        vm.expectRevert("Gateway/cannot-topup-with-nothing");
        router.requestDeposit(vault_, amount, self, self, 0);

        vm.expectRevert("CentrifugeRouter/insufficient-funds-to-topup");
        router.requestDeposit{value: lessGas}(vault_, amount, self, self, gasLimit);

        vm.expectRevert("Gateway/not-enough-gas-funds");
        router.requestDeposit{value: lessGas}(vault_, amount, self, self, lessGas);

        vm.expectRevert("PoolManager/unknown-vault");
        router.requestDeposit{value: lessGas}(makeAddr("maliciousVault"), amount, self, makeAddr("owner"), lessGas);

        vm.expectRevert("PoolManager/unknown-vault");
        router.requestDeposit{value: lessGas}(makeAddr("maliciousVault"), amount, self, self, lessGas);

        bytes[] memory calls = new bytes[](2);
        calls[0] = abi.encodeWithSelector(router.requestDeposit.selector, vault_, amount / 2, self, self, gasLimit);
        calls[1] = abi.encodeWithSelector(router.requestDeposit.selector, vault_, amount / 2, self, self, gasLimit);

        vm.expectRevert("CentrifugeRouter/insufficient-funds-to-topup");
        router.multicall{value: gasLimit}(calls);

        uint256 coverMoreThanItIsNeeded = gasLimit * calls.length + 1;
        assertEq(address(router).balance, 0);
        router.multicall{value: coverMoreThanItIsNeeded}(calls);
        assertEq(address(router).balance, 1);
    }

    // --- helpers ---
    function fulfillDepositRequest(ERC7540Vault vault, uint128 assetId, uint256 amount, address user)
        public
        returns (uint128 tranchesPayout)
    {
        uint128 price = 2 * 10 ** 18;
        tranchesPayout = uint128(amount * 10 ** 18 / price);
        assertApproxEqAbs(tranchesPayout, amount / 2, 2);
        centrifugeChain.isFulfilledDepositRequest(
            vault.poolId(),
            vault.trancheId(),
            bytes32(bytes20(user)),
            assetId,
            uint128(amount),
            tranchesPayout,
            uint128(amount)
        );
    }

    function fulfillRedeemRequest(ERC7540Vault vault, uint128 assetId, uint256 amount, address user)
        public
        returns (uint128 assetPayout)
    {
        uint128 price = 2 * 10 ** 18;
        assetPayout = uint128(amount * price / 10 ** 18);
        assertApproxEqAbs(assetPayout, amount * 2, 2);
        centrifugeChain.isFulfilledRedeemRequest(
            vault.poolId(), vault.trancheId(), bytes32(bytes20(user)), assetId, assetPayout, uint128(amount)
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
            deployVault(5, 6, restrictionManager, "name1", "symbol1", bytes16(bytes("1")), 1, address(erc20X));
        address vault2_ =
            deployVault(4, 6, restrictionManager, "name2", "symbol2", bytes16(bytes("2")), 2, address(erc20Y));
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
        (, total) = gateway.estimate(PAYLOAD_FOR_GAS_ESTIMATION);
    }
}
