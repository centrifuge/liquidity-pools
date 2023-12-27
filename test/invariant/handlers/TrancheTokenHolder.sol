// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.18;

// import {PoolManager} from "src/PoolManager.sol";
// import {MockCentrifugeChain} from "test/mocks/MockCentrifugeChain.sol";
// import "forge-std/Test.sol";

// interface ERC20Like {
//     function approve(address spender, uint256 amount) external returns (bool);
//     function balanceOf(address account) external view returns (uint256);
//     function totalSupply() external view returns (uint256);
// }

// contract TrancheTokenHolderHandler is Test {
//     // This handler only uses a single pool, tranche and user combination
//     uint64 poolId;
//     bytes16 trancheId;
//     uint128 currencyId;

//     ERC20Like public immutable trancheToken;
//     MockCentrifugeChain immutable centrifugeChain;
//     PoolManager immutable poolManager;

//     // Investor initially holds 10M tranche tokens on Centrifuge Chain
//     uint128 public investorBalanceOnCentrifugeChain = 10_000_000 * 10 ** 18;

//     uint256 public totalTransferredIn;
//     uint256 public totalTransferredOut;
//     address[] public allInvestors;
//     mapping(address => uint256) public investorTransferredIn;
//     mapping(address => uint256) public investorTransferredOut;

//     constructor(
//         uint64 poolId_,
//         bytes16 trancheId_,
//         uint128 currencyId_,
//         address mockCentrifugeChain_,
//         address poolManager_
//     ) {
//         poolId = poolId_;
//         trancheId = trancheId_;
//         currencyId = currencyId_;

//         centrifugeChain = MockCentrifugeChain(mockCentrifugeChain_);
//         poolManager = PoolManager(poolManager_);
//         trancheToken = ERC20Like(poolManager.getTrancheToken(poolId_, trancheId_));

//         allInvestors.push(address(this));
//     }

//     function addInvestor(uint64 poolId_, bytes16 trancheId_, address investor) public {
//         centrifugeChain.updateMember(poolId_, trancheId_, investor, type(uint64).max);
//         allInvestors.push(investor);
//     }

//     function transferIn(uint256 investorIndex, uint256 amount) public {
//         investorIndex = bound(investorIndex, 0, allInvestors.length - 1);
//         address investor = allInvestors[investorIndex];
//         amount = bound(amount, 0, uint256(investorBalanceOnCentrifugeChain));
//         centrifugeChain.incomingTransferTrancheTokens(
//             poolId, trancheId, uint64(block.chainid), investor, uint128(amount)
//         );

//         investorBalanceOnCentrifugeChain -= uint128(amount);
//         totalTransferredIn += amount;
//         investorTransferredIn[investor] += amount;
//     }

//     function transferOut(uint256 investorIndex, uint256 amount) public {
//         investorIndex = bound(investorIndex, 0, allInvestors.length - 1);
//         address investor = allInvestors[investorIndex];
//         amount = bound(amount, 0, trancheToken.balanceOf(investor));
//         vm.startPrank(investor);
//         trancheToken.approve(address(poolManager), amount);

//         bytes32 centrifugeChainAddress = "1";
//         poolManager.transferTrancheTokensToCentrifuge(poolId, trancheId, centrifugeChainAddress, uint128(amount));
//         vm.stopPrank();

//         investorBalanceOnCentrifugeChain += uint128(amount);
//         totalTransferredOut += amount;
//     }

//     function allInvestorsLength() public view returns (uint256) {
//         return allInvestors.length;
//     }
// }
