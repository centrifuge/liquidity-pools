// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.18;
pragma abicoder v2;

import {CentrifugeConnector} from "src/Connector.sol";
import {ConnectorGateway} from "src/routers/Gateway.sol";
import {ConnectorEscrow} from "src/Escrow.sol";
import {TrancheTokenFactory, MemberlistFactory} from "src/token/factory.sol";
import {RestrictedTokenLike} from "src/token/restricted.sol";
import {ERC20} from "src/token/erc20.sol";
import {MemberlistLike, Memberlist} from "src/token/memberlist.sol";
import {MockHomeConnector} from "./mock/MockHomeConnector.sol";
import {MockXcmRouter} from "./mock/MockXcmRouter.sol";
import {ConnectorAxelarEVMRouter} from "src/routers/axelar/EVMRouter.sol";
import {ConnectorMessages} from "../src/Messages.sol";
import {ConnectorPauseAdmin} from "../src/admin/PauseAdmin.sol";
import {ConnectorDelayedAdmin} from "../src/admin/DelayedAdmin.sol";
import "forge-std/Test.sol";
import "../src/Connector.sol";

interface ApproveLike {
    function approve(address, uint256) external;
}

contract MigrationsTest is Test {
    CentrifugeConnector bridgedConnector;
    ConnectorGateway gateway;
    MockHomeConnector connector;
    MockXcmRouter mockXcmRouter;
    ConnectorEscrow escrow;
    ConnectorPauseAdmin pauseAdmin;
    ConnectorDelayedAdmin delayedAdmin;

    function setUp() public {
        vm.chainId(1);
        uint256 shortWait = 24 hours;
        uint256 longWait = 48 hours;
        uint256 gracePeriod = 48 hours;
        address tokenFactory_ = address(new TrancheTokenFactory());
        address memberlistFactory_ = address(new MemberlistFactory());
        escrow = new ConnectorEscrow();

        bridgedConnector = new CentrifugeConnector(address(escrow), tokenFactory_, memberlistFactory_);

        mockXcmRouter = new MockXcmRouter(address(bridgedConnector));

        connector = new MockHomeConnector(address(mockXcmRouter));
        pauseAdmin = new ConnectorPauseAdmin();
        delayedAdmin = new ConnectorDelayedAdmin();

        gateway =
            new ConnectorGateway(address(bridgedConnector), address(mockXcmRouter), shortWait, longWait, gracePeriod);
        gateway.rely(address(pauseAdmin));
        gateway.rely(address(delayedAdmin));
        pauseAdmin.file("gateway", address(gateway));
        delayedAdmin.file("gateway", address(gateway));
        pauseAdmin.rely(address(gateway));
        delayedAdmin.rely(address(gateway));
        bridgedConnector.file("gateway", address(gateway));
        escrow.rely(address(bridgedConnector));
        mockXcmRouter.file("gateway", address(gateway));
        mockXcmRouter.rely(address(gateway));
        bridgedConnector.rely(address(gateway));
        escrow.rely(address(gateway));
    }

    function deployPoolAndTranche(
        CentrifugeConnector activeConnector,
        MockXcmRouter activeMockXcmRouter,
        uint64 poolId,
        bytes16 trancheId,
        string memory tokenName,
        string memory tokenSymbol,
        uint8 decimals,
        uint128 price
    ) public {
        connector = new MockHomeConnector(address(activeMockXcmRouter));
        connector.addPool(poolId);
        (uint64 actualPoolId,) = activeConnector.pools(poolId);
        assertEq(uint256(actualPoolId), uint256(poolId));

        connector.addTranche(poolId, trancheId, tokenName, tokenSymbol, decimals, price);
        activeConnector.deployTranche(poolId, trancheId);

        (
            address token_,
            uint256 latestPrice,
            ,
            string memory actualTokenName,
            string memory actualTokenSymbol,
            uint8 actualDecimals
        ) = activeConnector.tranches(poolId, trancheId);
        assertTrue(token_ != address(0));
        assertEq(latestPrice, price);

        assertEq(actualTokenName, bytes32ToString(stringToBytes32(tokenName)));
        assertEq(actualTokenSymbol, bytes32ToString(stringToBytes32(tokenSymbol)));
        assertEq(actualDecimals, decimals);

        RestrictedTokenLike token = RestrictedTokenLike(token_);
        assertEq(token.name(), bytes32ToString(stringToBytes32(tokenName)));
        assertEq(token.symbol(), bytes32ToString(stringToBytes32(tokenSymbol)));
        assertEq(token.decimals(), decimals);
    }

    function addMember(
        CentrifugeConnector activeConnector,
        MockXcmRouter activeMockXcmRouter,
        uint64 poolId,
        bytes16 trancheId,
        address user,
        uint64 validUntil
    ) public {
        connector = new MockHomeConnector(address(activeMockXcmRouter));
        (address token_,,,,,) = activeConnector.tranches(poolId, trancheId);
        connector.updateMember(poolId, trancheId, user, validUntil);

        RestrictedTokenLike token = RestrictedTokenLike(token_);
        assertTrue(token.hasMember(user));

        MemberlistLike memberlist = MemberlistLike(token.memberlist());
        assertEq(memberlist.members(user), validUntil);
    }

    function runFullInvestRedeemCycle(
        CentrifugeConnector activeConnector,
        MockXcmRouter activeMockXcmRouter,
        uint64 poolId,
        bytes16 trancheId,
        string memory tokenName,
        string memory tokenSymbol
    ) public {
        connector = new MockHomeConnector(address(activeMockXcmRouter));
        address user = address(0x123);
        uint64 validUntil = uint64(block.timestamp + 1000 days);
        address DAI = address(0x6B175474E89094C44Da98b954EedeAC495271d0F);
        uint8 decimals = ERC20(DAI).decimals();
        uint128 price = uint128(10 ** uint128(decimals));

        deployPoolAndTranche(
            activeConnector, activeMockXcmRouter, poolId, trancheId, tokenName, tokenSymbol, decimals, price
        );
        addMember(activeConnector, activeMockXcmRouter, poolId, trancheId, user, validUntil);
        (address token_,,,,,) = activeConnector.tranches(poolId, trancheId);

        // Add DAI to the pool
        uint128 currency = 1;
        connector.addCurrency(currency, DAI);
        connector.allowPoolCurrency(poolId, currency);

        // deal fake investor fake DAI and add allowance to escrow
        deal(DAI, user, 1000);
        vm.prank(user);
        ApproveLike(DAI).approve(address(activeConnector), 1000);
        // assertEq(ERC20(DAI).balanceOf(user), 1000);
        // TODO: activeConnector.requestDeposit(1000)

        // increase invest order and decrease by a smaller amount
        vm.startPrank(user);
        activeConnector.increaseInvestOrder(poolId, trancheId, DAI, 1000);
        assertEq(ERC20(DAI).balanceOf(user), 0);
        activeConnector.decreaseInvestOrder(poolId, trancheId, DAI, 100);
        vm.stopPrank();
        connector.incomingExecutedDecreaseInvestOrder(poolId, trancheId, user, currency, 100, 900); // TODO: Not implemeted yet
        // assertEq(ERC20(DAI).balanceOf(address(escrow)), 100);

        // Assume bot has triggered epoch execution. Then we can collect tranche tokens
        vm.prank(user);
        activeConnector.collectInvest(poolId, trancheId);
        uint128 trancheAmount = uint128(900 * price / 10 ** uint128(decimals));
        connector.incomingExecutedCollectInvest(poolId, trancheId, user, currency, 0, 900, trancheAmount); // TODO: Not implemeted yet
        // TODO: activeConnector.deposit(1000)
        // assertEq(ERC20(token_).balanceOf(user), trancheAmount);

        // time passes
        vm.warp(100 days);
        connector.updateTokenPrice(poolId, trancheId, price * 2);
        (, price,,,,) = activeConnector.tranches(poolId, trancheId);

        // user submits redeem order
        // TODO: activeConnector.requestRedeem(trancheAmount)
        vm.prank(user);
        activeConnector.increaseRedeemOrder(poolId, trancheId, DAI, trancheAmount);
        // assertEq(ERC20(token_).balanceOf(user), 0);

        //bot executs epoch, and user redeems
        vm.prank(user);
        activeConnector.collectRedeem(poolId, trancheId);
        uint128 daiAmount = uint128(trancheAmount * price / 10 ** uint128(decimals));
        connector.incomingExecutedCollectRedeem(poolId, trancheId, user, currency, daiAmount, 0, 0); // TODO: Not implemeted yet
            // TODO: activeConnector.redeem(trancheAmount)
            // assertEq(ERC20(DAI).balanceOf(user), daiAmount);
            // assertEq(ERC20(token).balanceOf(user), 0);
    }

    function adminTest(address pauseAdmin, address delayedAdmin, address gateway) public {
        ConnectorPauseAdmin(pauseAdmin).pause();
        assertTrue(ConnectorGateway(gateway).paused());
        ConnectorPauseAdmin(pauseAdmin).unpause();
        assertFalse(ConnectorGateway(gateway).paused());
        address fakeSpell = address(0xBEEF);
        ConnectorDelayedAdmin(delayedAdmin).schedule(fakeSpell);
        assertEq(ConnectorGateway(gateway).relySchedule(fakeSpell), block.timestamp + 48 hours);
        ConnectorDelayedAdmin(delayedAdmin).cancelSchedule(fakeSpell);
        assertEq(ConnectorGateway(gateway).relySchedule(fakeSpell), 0);
    }

    function mockAdminSetup() public {
        // Setup: Add a user with delayedAdmin rights and deny this test, which acts as the spell.
        address adminUser = address(0xFED);
        delayedAdmin.rely(adminUser);

        pauseAdmin.deny(address(this));
        delayedAdmin.deny(address(this));
        gateway.deny(address(this));
        bridgedConnector.deny(address(this));
        escrow.deny(address(this));

        // Mock the priviledge granting system
        vm.prank(adminUser);
        delayedAdmin.schedule(address(this));
        vm.warp(block.timestamp + 49 hours);
        gateway.executeScheduledRely(address(this));
    }

    function migrateConnectorState(
        CentrifugeConnector oldConnector,
        CentrifugeConnector newGateway,
        uint64[] memory poolIds,
        bytes16[] memory trancheIds
    ) public {
        for (uint256 i = 0; i < poolIds.length; i++) {
            uint64 poolId = poolIds[i];
            bytes16 trancheId = trancheIds[i];
            (
                address token,
                uint128 latestPrice,
                uint256 lastPriceUpdate,
                string memory tokenName,
                string memory tokenSymbol,
                uint8 decimals
            ) = oldConnector.tranches(poolId, trancheId);
            newGateway.addTranche(poolIds[i], trancheIds[i], tokenName, tokenSymbol, decimals, latestPrice);
        }
    }

    function checkConnectorStateMigration(
        CentrifugeConnector oldConnector,
        CentrifugeConnector newConnector,
        uint64[] memory poolIds,
        bytes16[] memory trancheIds
    ) public {
        for (uint256 i = 0; i < poolIds.length; i++) {
            uint64 poolId = poolIds[i];
            bytes16 trancheId = trancheIds[i];
            (address token, uint128 latestPrice,, string memory tokenName, string memory tokenSymbol,) =
                oldConnector.tranches(poolId, trancheId);
            (address newToken, uint128 newLatestPrice,, string memory newTokenName, string memory newTokenSymbol,) =
                newConnector.tranches(poolId, trancheId);
            assertEq(newToken, token);
            assertEq(newLatestPrice, latestPrice);
            assertEq(newTokenName, tokenName);
            assertEq(newTokenSymbol, tokenSymbol);
        }
    }

    function testMigrateGateway(uint64 poolId, bytes16 trancheId, string memory tokenName, string memory tokenSymbol)
        public
    {
        mockAdminSetup();

        // <--- Start of mock spell Contents --->
        gateway.relyContract(address(bridgedConnector), address(this));
        gateway.relyContract(address(escrow), address(this));
        gateway.relyContract(address(pauseAdmin), address(this));
        gateway.relyContract(address(delayedAdmin), address(this));
        gateway.relyContract(address(mockXcmRouter), address(this));

        ConnectorGateway newGateway = new ConnectorGateway(
            address(bridgedConnector),
            address(mockXcmRouter),
            24 hours,
            48 hours,
            48 hours
        );

        newGateway.rely(address(pauseAdmin));
        newGateway.rely(address(delayedAdmin));

        // file new gateway on other contracts
        pauseAdmin.file("gateway", address(newGateway));
        delayedAdmin.file("gateway", address(newGateway));
        pauseAdmin.rely(address(newGateway));
        delayedAdmin.rely(address(newGateway));
        bridgedConnector.file("gateway", address(newGateway));
        mockXcmRouter.file("gateway", address(newGateway));
        bridgedConnector.rely(address(newGateway));
        escrow.rely(address(newGateway));
        mockXcmRouter.rely(address(newGateway));

        // <--- End of mock spell Contents --->

        // Test that the migration was successful
        runFullInvestRedeemCycle(bridgedConnector, mockXcmRouter, poolId, trancheId, tokenName, tokenSymbol);
        adminTest(address(pauseAdmin), address(delayedAdmin), address(newGateway));
    }

    function testMigrateConnector(
        uint64 poolId1,
        bytes16 trancheId1,
        string memory tokenName1,
        string memory tokenSymbol1
    ) public {
        // Deply pool and tranche to old connector contract to migrate to new connector contract
        address DAI = address(0x6B175474E89094C44Da98b954EedeAC495271d0F);
        uint8 decimals = ERC20(DAI).decimals();
        uint128 price = uint128(10 ** uint128(decimals));
        deployPoolAndTranche(
            bridgedConnector, mockXcmRouter, poolId1, trancheId1, tokenName1, tokenSymbol1, decimals, price
        );
        mockAdminSetup();

        // <--- Start of mock spell Contents --->
        gateway.relyContract(address(bridgedConnector), address(this));
        gateway.relyContract(address(escrow), address(this));
        gateway.relyContract(address(pauseAdmin), address(this));
        gateway.relyContract(address(delayedAdmin), address(this));

        CentrifugeConnector newConnector =
        new CentrifugeConnector(address(escrow), address(bridgedConnector.tokenFactory()), address(bridgedConnector.memberlistFactory()));

        MockXcmRouter newMockRouter = new MockXcmRouter(address(newConnector));

        ConnectorGateway newGateway = new ConnectorGateway(
            address(newConnector),
            address(newMockRouter),
            24 hours,
            48 hours,
            48 hours
        );
        newGateway.rely(address(pauseAdmin));
        newGateway.rely(address(delayedAdmin));

        // file new gateway on other contracts
        pauseAdmin.file("gateway", address(newGateway));
        delayedAdmin.file("gateway", address(newGateway));
        newConnector.file("gateway", address(newGateway));
        newMockRouter.file("gateway", address(newGateway));
        newConnector.rely(address(newGateway));
        escrow.rely(address(newGateway));
        pauseAdmin.rely(address(newGateway));
        delayedAdmin.rely(address(newGateway));
        newMockRouter.rely(address(newGateway));

        uint64[] memory poolIds = new uint64[](1);
        poolIds[0] = poolId1;
        bytes16[] memory trancheIds = new bytes16[](1);
        trancheIds[0] = trancheId1;
        migrateConnectorState(bridgedConnector, newConnector, poolIds, trancheIds);

        // <--- End of mock spell Contents --->

        // uint64 poolId2 = poolId1 + 2;
        // bytes16 trancheId2 = bytes16(uint128(trancheId1) + 2);
        // string memory tokenName2 = string(abi.encodePacked(tokenName1, "2"));
        // string memory tokenSymbol2 = string(abi.encodePacked(tokenSymbol1, "2"));

        // checkConnectorStateMigration(bridgedConnector, newConnector, poolIds, trancheIds);
        // runFullInvestRedeemCycle(newConnector, newMockRouter, poolId2, trancheId2, tokenName2, tokenSymbol2);
        // adminTest(address(pauseAdmin), address(delayedAdmin), address(newGateway));
    }

    function testMigrateEscrow() public {}

    function testMigrateMessages() public {}

    function testMigrateRouter() public {}

    function testMigrateDelayedAdmin() public {}

    function testMigratePauseAdmin() public {}

    function stringToBytes32(string memory source) internal pure returns (bytes32 result) {
        bytes memory tempEmptyStringTest = bytes(source);
        if (tempEmptyStringTest.length == 0) {
            return 0x0;
        }

        assembly {
            result := mload(add(source, 32))
        }
    }

    function bytes32ToString(bytes32 _bytes32) internal pure returns (string memory) {
        uint8 i = 0;
        while (i < 32 && _bytes32[i] != 0) {
            i++;
        }

        bytes memory bytesArray = new bytes(i);
        for (i = 0; i < 32 && _bytes32[i] != 0; i++) {
            bytesArray[i] = _bytes32[i];
        }
        return string(bytesArray);
    }
}
