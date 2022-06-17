// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.7.6;
pragma abicoder v2;

import "forge-std/Test.sol";
import "src/Connector.sol";
import "src/routers/nomad/Router.sol";
import "./MockHomeConnector.sol";

contract ConnectorTest is Test {

    CentrifugeConnector bridgedConnector;
    ConnectorRouter bridgedRouter;
    MockHomeConnector homeConnector;

    function setUp() public {
        bridgedConnector = new CentrifugeConnector(address(this));
        bridgedRouter = new ConnectorRouter(address(bridgedConnector));
        bridgedConnector.file("router", address(bridgedRouter));

        homeConnector = new MockHomeConnector(address(bridgedRouter));
    }

    function testAddingPool(uint poolId) public {
        homeConnector.addPool(poolId);
        (uint actualPoolId) = bridgedConnector.pools(poolId);
        assertEq(actualPoolId, poolId);
    }
}
