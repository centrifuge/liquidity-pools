// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.26;

import "test/BaseTest.sol";

contract GatewayTest is BaseTest {
    // Deployment
    function testDeployment(address nonWard) public {
        vm.assume(
            nonWard != address(root) && nonWard != address(guardian) && nonWard != address(this)
                && nonWard != address(gateway)
        );

        // redeploying within test to increase coverage
        new Gateway(address(root), address(poolManager), address(investmentManager), address(gasService));

        // values set correctly
        assertEq(address(gateway.investmentManager()), address(investmentManager));
        assertEq(address(gateway.poolManager()), address(poolManager));
        assertEq(address(gateway.root()), address(root));
        assertEq(address(investmentManager.gateway()), address(gateway));
        assertEq(address(poolManager.gateway()), address(gateway));

        // gateway setup
        assertEq(gateway.quorum(), 3);
        assertEq(gateway.adapters(0), address(adapter1));
        assertEq(gateway.adapters(1), address(adapter2));
        assertEq(gateway.adapters(2), address(adapter3));

        // permissions set correctly
        assertEq(gateway.wards(address(root)), 1);
        assertEq(gateway.wards(address(guardian)), 1);
        assertEq(gateway.wards(nonWard), 0);
    }
}
