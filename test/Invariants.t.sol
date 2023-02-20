// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.7.6;
pragma abicoder v2;

import {CentrifugeConnector} from "src/Connector.sol";
import {MockHomeConnector} from "./mock/MockHomeConnector.sol";
import {ConnectorXCMRouter} from "src/routers/xcm/Router.sol";
import {RestrictedTokenFactory, MemberlistFactory} from "src/token/factory.sol";
import {ERC20Like} from "src/token/restricted.sol";
import {InvariantPoolManager} from "./accounts/PoolManager.sol";
import {InvariantInvestor} from "./accounts/Investor.sol";
import "forge-std/Test.sol";
import "../src/Connector.sol";

contract ConnectorInvariants is Test {
    CentrifugeConnector bridgedConnector;
    ConnectorXCMRouter bridgedRouter;
    MockHomeConnector connector;

    InvariantPoolManager poolManager;
    InvariantInvestor investor;

    address[] private targetContracts_;

    function setUp() public {
        address tokenFactory_ = address(new RestrictedTokenFactory());
        address memberlistFactory_ = address(new MemberlistFactory());
        bridgedConnector = new CentrifugeConnector(tokenFactory_, memberlistFactory_);
        connector = new MockHomeConnector(address(bridgedConnector));
        bridgedConnector.file("router", address(connector.router()));

        // Performs random pool and tranches creations
        poolManager = new InvariantPoolManager(connector);
        targetContracts_.push(address(poolManager));

        // Performs random transfers in and out
        investor = new InvariantInvestor(connector, bridgedConnector);
        targetContracts_.push(address(investor));
    }

    function targetContracts() public view returns (address[] memory) {
        return targetContracts_;
    }

    // Invariant 1: For every tranche that exists, the equivalent pool exists
    function invariant_trancheRequiresPool() external {
        for (uint256 i = 0; i < poolManager.allTranchesLength(); i++) {
            bytes16 trancheId = poolManager.allTranches(i);
            uint64 poolId = poolManager.trancheIdToPoolId(trancheId);
            (, uint256 createdAt) = bridgedConnector.pools(poolId);
            assertTrue(createdAt > 0);
        }
    }

    // Invariant 2: The tranche token supply should equal the sum of all
    // transfers in minus the sum of all the transfers out
    function invariant_tokenSolvency() external {
        (address token,,,,) = bridgedConnector.tranches(investor.fixedPoolId(), investor.fixedTrancheId());
        assertEq(ERC20Like(token).totalSupply(), investor.totalTransferredIn() - investor.totalTransferredOut());
    }
}
