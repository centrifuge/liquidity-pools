// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.18;
pragma abicoder v2;

import {CentrifugeConnector} from "src/Connector.sol";
import {MockHomeConnector} from "./mock/MockHomeConnector.sol";
import "./mock/MockXcmRouter.sol";
import {ConnectorGateway} from "src/routers/Gateway.sol";
import {RestrictedTokenFactory, MemberlistFactory} from "src/token/factory.sol";
import {InvariantPoolManager} from "./accounts/PoolManager.sol";
import "forge-std/Test.sol";
import "../src/Connector.sol";

contract ConnectorInvariants is Test {
    CentrifugeConnector bridgedConnector;
    MockHomeConnector connector;
    MockXcmRouter mockXcmRouter;
    ConnectorGateway gateway;

    InvariantPoolManager poolManager;

    address[] private targetContracts_;

    function setUp() public {
        address tokenFactory_ = address(new RestrictedTokenFactory());
        address memberlistFactory_ = address(new MemberlistFactory());
        bridgedConnector = new CentrifugeConnector(tokenFactory_, memberlistFactory_);
        mockXcmRouter = new MockXcmRouter(address(bridgedConnector));
        connector = new MockHomeConnector(address(mockXcmRouter));
        gateway = new ConnectorGateway(address(bridgedConnector), address(mockXcmRouter));

        mockXcmRouter.file("gateway", address(gateway));
        bridgedConnector.file("gateway", address(gateway));

        // Performs random pool and tranches creations
        poolManager = new InvariantPoolManager(connector);
        targetContracts_.push(address(poolManager));
    }

    function targetContracts() public view returns (address[] memory) {
        return targetContracts_;
    }

    // Invariant 1: For every tranche that exists, the equivalent pool exists
    function invariantTrancheRequiresPool() external {
        for (uint256 i = 0; i < poolManager.allTranchesLength(); i++) {
            bytes16 trancheId = poolManager.allTranches(i);
            uint64 poolId = poolManager.trancheIdToPoolId(trancheId);
            (, uint256 createdAt) = bridgedConnector.pools(poolId);
            assertTrue(createdAt > 0);
        }
    }
}
