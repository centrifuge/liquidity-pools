// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import "../TestSetup.t.sol";

contract GatewayTest is TestSetup {
    // Deployment
    function testDeployment() public {
        // values set correctly
        assertEq(address(gateway.investmentManager()), address(investmentManager));
        assertEq(address(gateway.poolManager()), address(poolManager));
        assertEq(address(gateway.root()), address(root));
        assertEq(address(investmentManager.gateway()), address(gateway));
        assertEq(address(poolManager.gateway()), address(gateway));

        // router setup
        assertEq(address(gateway.outgoingRouter()), address(mockXcmRouter));
        assert(gateway.incomingRouters(address(mockXcmRouter)));

        // permissions set correctly
        assertEq(gateway.wards(address(root)), 1);
        // assertEq(gateway.wards(self), 0); // deployer has no permissions
    }
}
