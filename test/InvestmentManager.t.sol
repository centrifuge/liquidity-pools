pragma solidity 0.8.21;
// SPDX-License-Identifier: AGPL-3.0-only
pragma abicoder v2;

import "./TestSetup.t.sol";

interface LiquidityPoolLike {
    function latestPrice() external view returns (uint128);
    function priceComputedAt() external view returns (uint64);
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
}
