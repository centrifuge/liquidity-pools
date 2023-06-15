// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.18;
pragma abicoder v2;

import {CentrifugeConnector} from "src/Connector.sol";
import {ConnectorEscrow} from "src/Escrow.sol";
import {MockHomeConnector} from "./mock/MockHomeConnector.sol";
import "./mock/MockXcmRouter.sol";
import {ERC20Like} from "src/token/restricted.sol";
import {ConnectorGateway} from "src/routers/Gateway.sol";
import {TrancheTokenFactory, MemberlistFactory} from "src/token/factory.sol";
import {InvariantPoolManager} from "./accounts/PoolManager.sol";
import {InvariantInvestor} from "./accounts/InvestorManager.sol";
import "forge-std/Test.sol";
import "../src/Connector.sol";

contract ConnectorInvariants is Test {
    CentrifugeConnector bridgedConnector;
    MockHomeConnector connector;
    MockXcmRouter mockXcmRouter;
    ConnectorGateway gateway;

    InvariantPoolManager poolManager;
    InvariantInvestor investor;

    address[] private targetContracts_;

    function setUp() public {
        address escrow_ = address(new ConnectorEscrow());
        address tokenFactory_ = address(new TrancheTokenFactory());
        address memberlistFactory_ = address(new MemberlistFactory());
        bridgedConnector = new CentrifugeConnector(escrow_, tokenFactory_, memberlistFactory_);
        mockXcmRouter = new MockXcmRouter(address(bridgedConnector));
        connector = new MockHomeConnector(address(mockXcmRouter));
        gateway = new ConnectorGateway(address(bridgedConnector), address(mockXcmRouter));

        mockXcmRouter.file("gateway", address(gateway));
        bridgedConnector.file("gateway", address(gateway));

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
        (address token,,,,,) = bridgedConnector.tranches(investor.fixedPoolId(), investor.fixedTrancheId());
        assertEq(ERC20Like(token).totalSupply(), investor.totalTransferredIn() - investor.totalTransferredOut());
    }

    // Invariant 3: An investor should not be able to transfer out more tranche tokens than were transferred in
    function invariant_investorSolvency() external {
        assertTrue(investor.totalTransferredIn() >= investor.totalTransferredOut());
        for (uint256 i = 0; i < investor.allInvestorsLength(); i++) {
            address investorAddress = investor.allInvestors(i);
            assertTrue(
                investor.investorTransferredIn(investorAddress) >= investor.investorTransferredOut(investorAddress)
            );
        }
    }

    // Invariant 4: The total supply of tranche tokens should equal the sum of all the investors balances
    function invariant_totalSupply() external {
        (address token,,,,,) = bridgedConnector.tranches(investor.fixedPoolId(), investor.fixedTrancheId());
        uint256 totalSupply = ERC20Like(token).totalSupply();
        uint256 totalBalance = 0;
        for (uint256 i = 0; i < investor.allInvestorsLength(); i++) {
            totalBalance += ERC20Like(token).balanceOf(investor.allInvestors(i));
        }
        assertEq(totalSupply, totalBalance);
    }
}
