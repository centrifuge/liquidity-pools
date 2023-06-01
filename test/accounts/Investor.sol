// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.18;
pragma abicoder v2;

import {MockHomeConnector} from "../mock/MockHomeConnector.sol";
import {CentrifugeConnector} from "src/Connector.sol";
import {ERC20Like} from "src/token/restricted.sol";
import {ConnectorMessages} from "src/Messages.sol";

import "forge-std/Test.sol";

contract InvariantInvestor is Test {
    MockHomeConnector connector;
    CentrifugeConnector bridgedConnector;

    // This handler only uses a single pool, tranche and user combination
    uint64 public fixedPoolId = 1;
    bytes16 public fixedTrancheId = "1";
    ERC20Like public fixedToken;

    // Investor initially holds 10M tranche tokens on Centrifuge Chain
    uint128 public investorBalanceOnCentrifugeChain = 10_000_000 * 10 ** 18;

    uint256 public totalTransferredIn;
    uint256 public totalTransferredOut;

    constructor(MockHomeConnector connector_, CentrifugeConnector bridgedConnector_) {
        connector = connector_;
        bridgedConnector = bridgedConnector_;

        connector.addPool(fixedPoolId);
        connector.addTranche(fixedPoolId, fixedTrancheId, "TKN", "Token", 18, uint128(1000));
        bridgedConnector.deployTranche(fixedPoolId, fixedTrancheId);
        connector.updateMember(fixedPoolId, fixedTrancheId, address(this), type(uint64).max);

        (address token,,,,,) = bridgedConnector.tranches(fixedPoolId, fixedTrancheId);
        fixedToken = ERC20Like(token);
    }

    function transferIn(uint256 amount) public {
        amount = bound(amount, 0, uint256(investorBalanceOnCentrifugeChain));
        connector.incomingTransferTrancheTokens(fixedPoolId, fixedTrancheId, 1, address(this), uint128(amount));

        investorBalanceOnCentrifugeChain -= uint128(amount);
        totalTransferredIn += amount;
    }

    function transferOut(uint256 amount) public {
        amount = bound(amount, 0, fixedToken.balanceOf(address(this)));
        fixedToken.approve(address(bridgedConnector), amount);
        bridgedConnector.transferTrancheTokensToCentrifuge(fixedPoolId, fixedTrancheId, "1", uint128(amount));

        investorBalanceOnCentrifugeChain += uint128(amount);
        totalTransferredOut += amount;
    }
}
