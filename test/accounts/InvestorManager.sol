// SPDX-License-Identifier: AGPL-3.0-only
// pragma solidity ^0.8.18;
// pragma abicoder v2;

// import {MockHomeConnector} from "../mock/MockHomeConnector.sol";
// import {CentrifugeConnector} from "src/Connector.sol";
// import {ERC20Like} from "src/token/restricted.sol";
// import {ConnectorMessages} from "src/Messages.sol";

// import "forge-std/Test.sol";

// contract InvariantInvestor is Test {
//     MockHomeConnector connector;
//     CentrifugeConnector bridgedConnector;

//     This handler only uses a single pool, tranche and user combination
//     uint64 public fixedPoolId = 1;
//     bytes16 public fixedTrancheId = "1";
//     ERC20Like public fixedToken;

//     Investor initially holds 10M tranche tokens on Centrifuge Chain
//     uint128 public investorBalanceOnCentrifugeChain = 10_000_000 * 10 ** 18;

//     uint256 public totalTransferredIn;
//     uint256 public totalTransferredOut;
//     address[] public allInvestors;
//     mapping(address => uint256) public investorTransferredIn;
//     mapping(address => uint256) public investorTransferredOut;

//     constructor(MockHomeConnector connector_, CentrifugeConnector bridgedConnector_) {
//         connector = connector_;
//         bridgedConnector = bridgedConnector_;

//         connector.addPool(fixedPoolId);
//         connector.addTranche(fixedPoolId, fixedTrancheId, "TKN", "Token", 18, uint128(1000));
//         bridgedConnector.deployTranche(fixedPoolId, fixedTrancheId);
//         connector.updateMember(fixedPoolId, fixedTrancheId, address(this), type(uint64).max);

//         (address token,,,,,) = bridgedConnector.tranches(fixedPoolId, fixedTrancheId);
//         fixedToken = ERC20Like(token);
//         allInvestors.push(address(this));
//     }

//     function addInvestor(uint64 poolId, bytes16 trancheId, address investor, uint128 amount) public {
//         connector.updateMember(poolId, trancheId, investor, type(uint64).max);
//         allInvestors.push(investor);
//     }

//     function transferIn(uint256 investorIndex, uint256 amount) public {
//         investorIndex = bound(investorIndex, 0, allInvestors.length - 1);
//         address investor = allInvestors[investorIndex];
//         amount = bound(amount, 0, uint256(investorBalanceOnCentrifugeChain));
//         connector.incomingTransferTrancheTokens(fixedPoolId, fixedTrancheId, 1, investor, uint128(amount));

//         investorBalanceOnCentrifugeChain -= uint128(amount);
//         totalTransferredIn += amount;
//         investorTransferredIn[investor] += amount;
//     }

//     function transferOut(uint256 investorIndex, uint256 amount) public {
//         investorIndex = bound(investorIndex, 0, allInvestors.length - 1);
//         address investor = allInvestors[investorIndex];
//         amount = bound(amount, 0, fixedToken.balanceOf(investor));
//         vm.startPrank(investor);
//         fixedToken.approve(address(bridgedConnector), amount);
//         bridgedConnector.transferTrancheTokensToCentrifuge(fixedPoolId, fixedTrancheId, "1", uint128(amount));
//         vm.stopPrank();

//         investorBalanceOnCentrifugeChain += uint128(amount);
//         totalTransferredOut += amount;
//     }

//     function allInvestorsLength() public view returns (uint256) {
//         return allInvestors.length;
//     }
// }
