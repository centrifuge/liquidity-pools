pragma solidity 0.8.21;
// SPDX-License-Identifier: AGPL-3.0-only
pragma abicoder v2;

import "./TestSetup.t.sol";

interface LiquidityPoolLike {
    function latestPrice() external view returns (uint128);
    function lastPriceUpdate() external view returns (uint256);
}

contract InvestmentManagerTest is TestSetup {
    // Deployment
    function testDeployment() public {
        // values set correctly
        assertEq(address(investmentManager.escrow()), address(escrow));
        assertEq(address(investmentManager.userEscrow()), address(userEscrow));
        assertEq(address(investmentManager.gateway()), address(gateway));
        assertEq(address(investmentManager.poolManager()), address(poolManager));
        assertEq(address(gateway.investmentManager()), address(investmentManager));
        assertEq(address(poolManager.investmentManager()), address(investmentManager));

        // permissions set correctly
        assertEq(investmentManager.wards(address(root)), 1);
        assertEq(investmentManager.wards(address(poolManager)), 1);
        assertEq(escrow.wards(address(investmentManager)), 1);
        assertEq(userEscrow.wards(address(investmentManager)), 1);
        // assertEq(investmentManager.wards(self), 0); // deployer has no permissions
    }

    // --- Administration ---
    function testFile(address random) public {
        // fail: unrecognized param
        vm.expectRevert(bytes("InvestmentManager/file-unrecognized-param"));
        investmentManager.file("random", self);

        assertEq(address(investmentManager.gateway()), address(gateway));
        assertEq(address(investmentManager.poolManager()), address(poolManager));
        // success
        investmentManager.file("poolManager", random);
        assertEq(address(investmentManager.poolManager()), random);
        investmentManager.file("gateway", random);
        assertEq(address(investmentManager.gateway()), random);

        // remove self from wards
        investmentManager.deny(self);
        // auth fail
        vm.expectRevert(bytes("Auth/not-authorized"));
        investmentManager.file("poolManager", random);
    }

    function testUpdatingTokenPriceWorks(
        uint64 poolId,
        uint8 decimals,
        uint128 currencyId,
        string memory tokenName,
        string memory tokenSymbol,
        bytes16 trancheId,
        uint128 price
    ) public {
        decimals = uint8(bound(decimals, 1, 18));
        vm.assume(poolId > 0);
        vm.assume(trancheId > 0);
        vm.assume(currencyId > 0);
        centrifugeChain.addPool(poolId); // add pool
        centrifugeChain.addTranche(poolId, trancheId, tokenName, tokenSymbol, decimals); // add tranche
        centrifugeChain.addCurrency(currencyId, address(erc20)); // add currency
        centrifugeChain.allowInvestmentCurrency(poolId, currencyId);

        poolManager.deployTranche(poolId, trancheId);
        LiquidityPoolLike lPool = LiquidityPoolLike(poolManager.deployLiquidityPool(poolId, trancheId, address(erc20)));

        centrifugeChain.updateTrancheTokenPrice(poolId, trancheId, currencyId, price);
        assertEq(lPool.latestPrice(), price);
        assertEq(lPool.lastPriceUpdate(), block.timestamp);
    }

    function testUpdatingTokenPriceAsNonRouterFails(
        uint64 poolId,
        uint8 decimals,
        uint128 currency,
        string memory tokenName,
        string memory tokenSymbol,
        bytes16 trancheId,
        uint128 price
    ) public {
        decimals = uint8(bound(decimals, 1, 18));
        vm.assume(currency > 0);
        ERC20 erc20 = _newErc20("X's Dollar", "USDX", 18);
        centrifugeChain.addPool(poolId); // add pool
        centrifugeChain.addTranche(poolId, trancheId, tokenName, tokenSymbol, decimals); // add tranche
        centrifugeChain.addCurrency(currency, address(erc20));
        centrifugeChain.allowInvestmentCurrency(poolId, currency);
        poolManager.deployTranche(poolId, trancheId);
        poolManager.deployLiquidityPool(poolId, trancheId, address(erc20));

        vm.expectRevert(bytes("InvestmentManager/not-the-gateway"));
        investmentManager.updateTrancheTokenPrice(poolId, trancheId, currency, price);
    }

    function testUpdatingTokenPriceForNonExistentTrancheFails(
        uint64 poolId,
        bytes16 trancheId,
        uint128 currencyId,
        uint128 price
    ) public {
        centrifugeChain.addPool(poolId);

        vm.expectRevert(bytes(""));
        centrifugeChain.updateTrancheTokenPrice(poolId, trancheId, currencyId, price);
    }


    // --- RequestDeposit ---

    function testRequestDeposit_failsIfAmountIsZero() public {
        address sender = makeAddr("sender");
        address user = makeAddr("user");
        LiquidityPool lPool = LiquidityPool(deploySimplePool());
        vm.expectRevert(bytes("InvestmentManager/zero-amount-not-allowed"));
        investmentManager.requestDeposit(address(lPool), 0, sender, user);
    }

    function testRequestDeposit_failsIfCurrencyNotAllowed() public {
        address sender = makeAddr("sender");
        address user = makeAddr("user");
        LiquidityPool lPool = LiquidityPool(deploySimplePool());
        centrifugeChain.disallowInvestmentCurrency(lPool.poolId(), poolManager.currencyAddressToId(lPool.asset()));
        vm.expectRevert(bytes("InvestmentManager/currency-not-allowed"));
        investmentManager.requestDeposit(address(lPool), 1e18, sender, user);
    }

    function testRequestDeposit_failsIfSenderIsRestricted() public {
        address sender = makeAddr("sender");
        address user = makeAddr("user");
        LiquidityPool lPool = LiquidityPool(deploySimplePool());
        vm.expectRevert(bytes("InvestmentManager/sender-is-restricted"));
        investmentManager.requestDeposit(address(lPool), 1e18, sender, user);
    }

    function testRequestDeposit_failsIfTransferIsRestricted() public {
        address sender = makeAddr("sender");
        address user = makeAddr("user");
        LiquidityPool lPool = LiquidityPool(deploySimplePool());
        centrifugeChain.updateMember(lPool.poolId(), lPool.trancheId(), sender, type(uint64).max);
        vm.expectRevert(bytes("InvestmentManager/transfer-not-allowed"));
        investmentManager.requestDeposit(address(lPool), 1e18, sender, user);
    }

    function testRequestDeposit() public {
        address sender = makeAddr("sender");
        address user = makeAddr("user");
        LiquidityPool lPool = LiquidityPool(deploySimplePool());
        centrifugeChain.updateMember(lPool.poolId(), lPool.trancheId(), sender, type(uint64).max);
        centrifugeChain.updateMember(lPool.poolId(), lPool.trancheId(), user, type(uint64).max);
        vm.prank(address(lPool));
        vm.expectCall(address(gateway), abi.encodeCall(gateway.increaseInvestOrder, (lPool.poolId(), lPool.trancheId(), user, poolManager.currencyAddressToId(lPool.asset()), 1e18)));
        investmentManager.requestDeposit(address(lPool), 1e18, sender, user);
    }


    // --- RequestRedeem ---

    function testRequestRedeem_failsIfAmountIsZero() public {
        address sender = makeAddr("sender");
        address user = makeAddr("user");
        LiquidityPool lPool = LiquidityPool(deploySimplePool());

        vm.expectRevert(bytes("InvestmentManager/zero-amount-not-allowed"));
        vm.prank(address(lPool));
        investmentManager.requestRedeem(address(lPool), 0, user);
    }

    function testRequestRedeem_failsIfCurrencyNotAllowed() public {
        address sender = makeAddr("sender");
        address user = makeAddr("user");
        LiquidityPool lPool = LiquidityPool(deploySimplePool());

        centrifugeChain.disallowInvestmentCurrency(lPool.poolId(), poolManager.currencyAddressToId(lPool.asset()));
        vm.expectRevert(bytes("InvestmentManager/currency-not-allowed"));
        vm.prank(address(lPool));
        investmentManager.requestRedeem(address(lPool), 1e18, user);   
    }

    function testRequestRedeem() public {
        address sender = makeAddr("sender");
        address user = makeAddr("user");
        LiquidityPool lPool = LiquidityPool(deploySimplePool());

        vm.prank(address(lPool));
        vm.expectCall(address(gateway), abi.encodeCall(gateway.increaseRedeemOrder, (lPool.poolId(), lPool.trancheId(), user, poolManager.currencyAddressToId(lPool.asset()), 1e18)));
        investmentManager.requestRedeem(address(lPool), 1e18, user);
    }


    // --- DecreaseDepositRequest ---

    function testDecreaseDepositRequest() public {
        address sender = makeAddr("sender");
        address user = makeAddr("user");
        LiquidityPool lPool = LiquidityPool(deploySimplePool());
        
        vm.prank(address(lPool));
        vm.expectCall(address(gateway), abi.encodeCall(gateway.decreaseInvestOrder, (lPool.poolId(), lPool.trancheId(), sender, poolManager.currencyAddressToId(lPool.asset()), 0.5e18)));
        investmentManager.decreaseDepositRequest(address(lPool), 0.5e18, sender);
    }


    // --- DecreaseRedeemRequest ---

    function testDecreaseRedeemRequest_failsIfTransferIsRestricted() public {
        address sender = makeAddr("sender");
        address user = makeAddr("user");
        LiquidityPool lPool = LiquidityPool(deploySimplePool());
        
        vm.prank(address(lPool));
        vm.expectRevert(bytes("InvestmentManager/transfer-not-allowed"));
        investmentManager.decreaseRedeemRequest(address(lPool), 0.5e18, sender);
    }

    function testDecreaseRedeemRequest() public {
        address sender = makeAddr("sender");
        address user = makeAddr("user");
        LiquidityPool lPool = LiquidityPool(deploySimplePool());
        centrifugeChain.updateMember(lPool.poolId(), lPool.trancheId(), sender, type(uint64).max);
        
        vm.prank(address(lPool));
        vm.expectCall(address(gateway), abi.encodeCall(gateway.decreaseRedeemOrder, (lPool.poolId(), lPool.trancheId(), sender, poolManager.currencyAddressToId(lPool.asset()), 0.5e18)));
        investmentManager.decreaseRedeemRequest(address(lPool), 0.5e18, sender);
    }


    // --- CancelDepositRequest ---

    function testCancelDepositRequest() public {
        address sender = makeAddr("sender");
        address user = makeAddr("user");
        LiquidityPool lPool = LiquidityPool(deploySimplePool());

        vm.prank(address(lPool));
        vm.expectCall(address(gateway), abi.encodeCall(gateway.cancelInvestOrder, (lPool.poolId(), lPool.trancheId(), sender, poolManager.currencyAddressToId(lPool.asset()))));
        investmentManager.cancelDepositRequest(address(lPool), sender);
    }


    // --- CancelRedeemRequest ---

    function testCancelRedeemRequest_failsIfTransferIsRestricted() public {
        address sender = makeAddr("sender");
        address user = makeAddr("user");
        LiquidityPool lPool = LiquidityPool(deploySimplePool());

        vm.prank(address(lPool));
        vm.expectRevert(bytes("InvestmentManager/transfer-not-allowed"));
        investmentManager.cancelRedeemRequest(address(lPool), sender);
    }


    function testCancelRedeemRequest() public {
        address sender = makeAddr("sender");
        address user = makeAddr("user");
        LiquidityPool lPool = LiquidityPool(deploySimplePool());
        centrifugeChain.updateMember(lPool.poolId(), lPool.trancheId(), sender, type(uint64).max);

        vm.prank(address(lPool));
        vm.expectCall(address(gateway), abi.encodeCall(gateway.cancelRedeemOrder, (lPool.poolId(), lPool.trancheId(), sender, poolManager.currencyAddressToId(lPool.asset()))));
        investmentManager.cancelRedeemRequest(address(lPool), sender);
    }
}
