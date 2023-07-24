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
        bridgedConnector.file("gateway", address(gateway));
        escrow.rely(address(bridgedConnector));
        mockXcmRouter.file("gateway", address(gateway));
        bridgedConnector.rely(address(gateway));
        escrow.rely(address(gateway));
    }

    function deployPoolAndTranche(
        uint64 poolId,
        bytes16 trancheId,
        string memory tokenName,
        string memory tokenSymbol,
        uint8 decimals,
        uint128 price
    ) public {
        connector.addPool(poolId);
        (uint64 actualPoolId,) = bridgedConnector.pools(poolId);
        assertEq(uint256(actualPoolId), uint256(poolId));

        connector.addTranche(poolId, trancheId, tokenName, tokenSymbol, decimals, price);
        bridgedConnector.deployTranche(poolId, trancheId);

        (
            address token_,
            uint256 latestPrice,
            ,
            string memory actualTokenName,
            string memory actualTokenSymbol,
            uint8 actualDecimals
        ) = bridgedConnector.tranches(poolId, trancheId);
        assertTrue(token_ != address(0));
        assertEq(latestPrice, price);

        assertEq(actualTokenName, bytes32ToString(stringToBytes32(tokenName)));
        assertEq(actualTokenSymbol, bytes32ToString(stringToBytes32(tokenSymbol)));
        assertEq(actualDecimals, decimals);

        RestrictedTokenLike token = RestrictedTokenLike(token_);
        assertEq(token.name(), bytes32ToString(stringToBytes32(tokenName)));
        assertEq(token.symbol(), bytes32ToString(stringToBytes32(tokenSymbol)));
        assertEq(token.decimals(), decimals);
        Memberlist(token.memberlist());
    }

    function addMember(uint64 poolId, bytes16 trancheId, address user, uint64 validUntil) public {
        (address token_,,,,,) = bridgedConnector.tranches(poolId, trancheId);
        connector.updateMember(poolId, trancheId, user, validUntil);

        RestrictedTokenLike token = RestrictedTokenLike(token_);
        assertTrue(token.hasMember(user));

        MemberlistLike memberlist = MemberlistLike(token.memberlist());
        assertEq(memberlist.members(user), validUntil);
    }

    function runFullInvestRedeemCycle(uint64 poolId, bytes16 trancheId, string memory tokenName, string memory tokenSymbol)
        public
    {
        address user = address(0x123);
        uint64 validUntil = uint64(block.timestamp + 1000 days);
        address DAI = address(0x6B175474E89094C44Da98b954EedeAC495271d0F);
        uint8 decimals = ERC20(DAI).decimals();
        uint128 price = uint128(10 ** uint128(decimals));

        deployPoolAndTranche(poolId, trancheId, tokenName, tokenSymbol, decimals, price);
        addMember(poolId, trancheId, user, validUntil);
        (address token_,,,,,) = bridgedConnector.tranches(poolId, trancheId);

        // Add DAI to the pool
        uint128 currency = 1;
        connector.addCurrency(currency, DAI);
        connector.allowPoolCurrency(poolId, currency);

        // deal fake investor fake DAI and add allowance to escrow
        deal(DAI, user, 1000);
        vm.prank(user);
        ApproveLike(DAI).approve(address(bridgedConnector), 1000);
        // assertEq(ERC20(DAI).balanceOf(user), 1000);
        // TODO: bridgedConnector.requestDeposit(1000)

        // increase invest order and decrease by a smaller amount
        vm.startPrank(user);
        bridgedConnector.increaseInvestOrder(poolId, trancheId, DAI, 1000);
        assertEq(ERC20(DAI).balanceOf(user), 0);
        bridgedConnector.decreaseInvestOrder(poolId, trancheId, DAI, 100);
        vm.stopPrank();
        connector.incomingExecutedDecreaseInvestOrder(poolId, trancheId, user, currency, 100, 900); // TODO: Not implemeted yet
        // assertEq(ERC20(DAI).balanceOf(address(escrow)), 100);

        // Assume bot has triggered epoch execution. Then we can collect tranche tokens
        vm.prank(user);
        bridgedConnector.collectInvest(poolId, trancheId);
        uint128 trancheAmount = uint128(900 * price / 10 ** uint128(decimals));
        connector.incomingExecutedCollectInvest(poolId, trancheId, user, currency, 0, 900, trancheAmount); // TODO: Not implemeted yet
        // TODO: bridgedConnector.deposit(1000)
        // assertEq(ERC20(token_).balanceOf(user), trancheAmount);

        // time passes
        vm.warp(100 days);
        connector.updateTokenPrice(poolId, trancheId, price * 2);
        (, price,,,,) = bridgedConnector.tranches(poolId, trancheId);

        // user submits redeem order
        // TODO: bridgedConnector.requestRedeem(trancheAmount)
        vm.prank(user);
        bridgedConnector.increaseRedeemOrder(poolId, trancheId, DAI, trancheAmount);
        // assertEq(ERC20(token_).balanceOf(user), 0);

        //bot executs epoch, and user redeems
        vm.prank(user);
        bridgedConnector.collectRedeem(poolId, trancheId);
        uint128 daiAmount = uint128(trancheAmount * price / 10 ** uint128(decimals));
        connector.incomingExecutedCollectRedeem(poolId, trancheId, user, currency, daiAmount, 0, 0); // TODO: Not implemeted yet
            // TODO: bridgedConnector.redeem(trancheAmount)
            // assertEq(ERC20(DAI).balanceOf(user), daiAmount);
            // assertEq(ERC20(token).balanceOf(user), 0);
    }

    function pauseTest(address pauseAdmin, address gateway) public {
        ConnectorPauseAdmin(pauseAdmin).pause();
        assertTrue(ConnectorGateway(gateway).paused());
        ConnectorPauseAdmin(pauseAdmin).unpause();
        assertFalse(ConnectorGateway(gateway).paused());
    }

    function testMigrateGateway(uint64 poolId, bytes16 trancheId, string memory tokenName, string memory tokenSymbol)
        public
    {
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
        bridgedConnector.file("gateway", address(newGateway));
        mockXcmRouter.file("gateway", address(newGateway));
        bridgedConnector.rely(address(newGateway));
        escrow.rely(address(newGateway));
        runFullInvestRedeemCycle(poolId, trancheId, tokenName, tokenSymbol);
        pauseTest(address(pauseAdmin), address(newGateway));
    }

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
