pragma solidity 0.8.21;
// SPDX-License-Identifier: AGPL-3.0-only
pragma abicoder v2;

import "test/BaseTest.sol";

interface LiquidityPoolLike {
    function priceComputedAt() external view returns (uint64);
}

contract InvestmentManagerTest is BaseTest {
    // Deployment
    function testDeployment(address nonWard) public {
        vm.assume(
            nonWard != address(root) && nonWard != address(liquidityPoolFactory) && nonWard != address(gateway)
                && nonWard != address(this)
        );

        // values set correctly
        assertEq(address(investmentManager.escrow()), address(escrow));
        assertEq(address(investmentManager.gateway()), address(gateway));
        assertEq(address(investmentManager.poolManager()), address(poolManager));
        assertEq(address(gateway.investmentManager()), address(investmentManager));
        assertEq(address(poolManager.investmentManager()), address(investmentManager));

        // permissions set correctly
        assertEq(investmentManager.wards(address(root)), 1);
        assertEq(investmentManager.wards(address(gateway)), 1);
        assertEq(investmentManager.wards(nonWard), 0);
    }

    // --- Administration ---
    function testFile() public {
        // fail: unrecognized param
        vm.expectRevert(bytes("InvestmentManager/file-unrecognized-param"));
        investmentManager.file("random", self);

        assertEq(address(investmentManager.gateway()), address(gateway));
        assertEq(address(investmentManager.poolManager()), address(poolManager));
        // success
        investmentManager.file("poolManager", randomUser);
        assertEq(address(investmentManager.poolManager()), randomUser);
        investmentManager.file("gateway", randomUser);
        assertEq(address(investmentManager.gateway()), randomUser);

        // remove self from wards
        investmentManager.deny(self);
        // auth fail
        vm.expectRevert(bytes("Auth/not-authorized"));
        investmentManager.file("poolManager", randomUser);
    }
}
