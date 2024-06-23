// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

// import {InvestmentManager} from "src/InvestmentManager.sol";
// import {Gateway} from "src/gateway/Gateway.sol";
// import {MockCentrifugeChain} from "test/mocks/MockCentrifugeChain.sol";
// import {Escrow} from "src/Escrow.sol";
// import {Guardian} from "src/admin/Guardian.sol";
// import {MockRouter} from "test/mocks/MockRouter.sol";
// import {PoolManager, Pool, Tranche} from "src/PoolManager.sol";
// import {ERC20} from "src/token/ERC20.sol";
// import {TrancheToken} from "src/token/Tranche.sol";
// import {ERC7540VaultTest} from "test/unit/ERC7540Vault.t.sol";
// import {PermissionlessRouter} from "test/mocks/PermissionlessRouter.sol";
// import {Root} from "src/Root.sol";
// import {ERC7540Vault} from "src/ERC7540Vault.sol";
// import {AxelarScript} from "script/Axelar.s.sol";
// import "script/Deployer.sol";
// import "src/libraries/MathLib.sol";
// import "forge-std/Test.sol";

// interface ApproveLike {
//     function approve(address, uint256) external;
// }

// interface WardLike {
//     function wards(address who) external returns (uint256);
// }

// interface HookLike {
//     function updateMember(address user, uint64 validUntil) external;
// }

// contract DeployTest is Test, Deployer {
//     using MathLib for uint256;

//     uint8 constant PRICE_DECIMALS = 18;

//     address self;
//     ERC20 erc20;
//     address[] pausers;

//     function setUp() public {
//         deploy(address(this));
//         PermissionlessRouter router = new PermissionlessRouter(address(aggregator));
//         wire(address(router));

//         // overwrite deployed guardian with a new mock safe guardian
//         pausers = new address[](3);
//         pausers[0] = makeAddr("pauser1");
//         pausers[1] = makeAddr("pauser2");
//         pausers[2] = makeAddr("pauser3");
//         adminSafe = address(new MockSafe(pausers, 1));
//         guardian = new Guardian(adminSafe, address(root), address(aggregator));
//         root.rely(address(guardian));

//         erc20 = newErc20("Test", "TEST", 6);
//         self = address(this);

//         removeDeployerAccess(address(router), address(this));
//     }

//     function testDeployerHasNoAccess() public {
//         vm.expectRevert("Auth/not-authorized");
//         root.relyContract(address(investmentManager), address(1));
//         assertEq(root.wards(address(this)), 0);
//         assertEq(investmentManager.wards(address(this)), 0);
//         assertEq(poolManager.wards(address(this)), 0);
//         assertEq(escrow.wards(address(this)), 0);
//         assertEq(gateway.wards(address(this)), 0);
//         assertEq(aggregator.wards(address(this)), 0);
//         // check factories
//         assertEq(WardLike(trancheTokenFactory).wards(address(this)), 0);
//         assertEq(WardLike(vaultFactory).wards(address(this)), 0);
//         assertEq(WardLike(restrictionManagerFactory).wards(address(this)), 0);
//     }

//     function testAdminSetup(address nonAdmin, address nonPauser) public {
//         vm.assume(nonAdmin != adminSafe);
//         vm.assume(nonPauser != pausers[0] && nonPauser != pausers[1] && nonPauser != pausers[2]);

//         assertEq(address(guardian.safe()), adminSafe);
//         for (uint256 i = 0; i < pausers.length; i++) {
//             assertEq(MockSafe(adminSafe).isOwner(pausers[i]), true);
//         }
//         assertEq(MockSafe(adminSafe).isOwner(nonPauser), false);
//     }

//     function testDeployAndInvestRedeem(
//         uint64 poolId,
//         string memory tokenName,
//         string memory tokenSymbol,
//         bytes16 trancheId,
//         uint8 decimals,
//         uint8 restrictionSet
//     ) public {
//         vm.assume(decimals <= 18 && decimals > 0);
//         uint128 price = uint128(2 * 10 ** PRICE_DECIMALS); //TODO: fuzz price
//         uint256 amount = 1000 * 10 ** erc20.decimals();
//         uint64 validUntil = uint64(block.timestamp + 1000 days);
//         address vault_ = deployPoolAndTranche(poolId, trancheId, tokenName, tokenSymbol, decimals, restrictionSet);
//         ERC7540Vault vault = ERC7540Vault(vault_);
//         TrancheToken trancheToken = TrancheToken(address(vault.share()));

//         deal(address(erc20), self, amount);

//         vm.prank(address(gateway));
//         HookLike(trancheToken.hook()).updateMember(self, validUntil);

//         depositMint(poolId, trancheId, price, amount, vault);
//         amount = trancheToken.balanceOf(self);

//         redeemWithdraw(poolId, trancheId, price, amount, vault);
//     }

//     function depositMint(uint64 poolId, bytes16 trancheId, uint128 price, uint256 amount, ERC7540Vault vault) public
// {
//         erc20.approve(address(vault), amount); // add allowance
//         vault.requestDeposit(amount, self, self, "");

//         // ensure funds are locked in escrow
//         assertEq(erc20.balanceOf(address(escrow)), amount);
//         assertEq(erc20.balanceOf(self), 0);

//         // trigger executed collectInvest
//         uint128 _assetId = poolManager.assetToId(address(erc20)); // retrieve assetId

//         TrancheToken trancheToken = TrancheToken(address(vault.share()));
//         uint128 shares = (
//             amount.mulDiv(
//                 10 ** (PRICE_DECIMALS - erc20.decimals() + trancheToken.decimals()), price, MathLib.Rounding.Down
//             )
//         ).toUint128();

//         // Assume an epoch execution happens on cent chain
//         // Assume a bot calls collectInvest for this user on cent chain

//         vm.prank(address(gateway));
//         investmentManager.fulfillDepositRequest(poolId, trancheId, self, _assetId, uint128(amount), shares, 0);

// uint256 div = 2;
// vault.deposit(amount / div, self, self);

//         uint256 div = 2;
//         vault.deposit(amount / div, self);

//         assertEq(trancheToken.balanceOf(self), shares / div);
//         assertEq(trancheToken.balanceOf(address(escrow)), shares - shares / div);
//         assertEq(vault.maxMint(self), shares - shares / div);
//         assertEq(vault.maxDeposit(self), amount - amount / div); // max deposit

//         vault.mint(vault.maxMint(self), self);

//         assertEq(trancheToken.balanceOf(self), shares);
//         assertTrue(trancheToken.balanceOf(address(escrow)) <= 1);
//         assertTrue(vault.maxMint(self) <= 1);
//     }

//     function redeemWithdraw(uint64 poolId, bytes16 trancheId, uint128 price, uint256 amount, ERC7540Vault vault)
//         public
//     {
//         vault.requestRedeem(amount, address(this), address(this), "");

//         // redeem
//         TrancheToken trancheToken = TrancheToken(address(vault.share()));
//         uint128 _assetId = poolManager.assetToId(address(erc20)); // retrieve assetId
//         uint128 assets = (
//             amount.mulDiv(price, 10 ** (18 - erc20.decimals() + trancheToken.decimals()), MathLib.Rounding.Down)
//         ).toUint128();
//         // Assume an epoch execution happens on cent chain
//         // Assume a bot calls collectRedeem for this user on cent chain
//         vm.prank(address(gateway));
//         investmentManager.fulfillRedeemRequest(poolId, trancheId, self, _assetId, assets, uint128(amount));

//         assertEq(vault.maxWithdraw(self), assets);
//         assertEq(vault.maxRedeem(self), amount);
//         assertEq(trancheToken.balanceOf(address(escrow)), 0);

//         uint128 div = 2;
//         vault.redeem(amount / div, self, self);
//         assertEq(trancheToken.balanceOf(self), 0);
//         assertEq(trancheToken.balanceOf(address(escrow)), 0);
//         assertEq(erc20.balanceOf(self), assets / div);
//         assertEq(vault.maxWithdraw(self), assets / div);
//         assertEq(vault.maxRedeem(self), amount / div);

//         vault.withdraw(vault.maxWithdraw(self), self, self);
//         assertEq(trancheToken.balanceOf(self), 0);
//         assertEq(trancheToken.balanceOf(address(escrow)), 0);
//         assertEq(erc20.balanceOf(self), assets);
//         assertEq(vault.maxWithdraw(self), 0);
//         assertEq(vault.maxRedeem(self), 0);
//     }

//     // helpers

//     function deployPoolAndTranche(
//         uint64 poolId,
//         bytes16 trancheId,
//         string memory tokenName,
//         string memory tokenSymbol,
//         uint8 decimals,
//         address hook
//     ) public returns (address) {
//         vm.startPrank(address(gateway));
//         poolManager.addPool(poolId);
//         poolManager.addTranche(poolId, trancheId, tokenName, tokenSymbol, decimals, restrictionSet);
//         poolManager.addAsset(1, address(erc20));
//         poolManager.allowAsset(poolId, 1);
//         vm.stopPrank();

//         poolManager.deployTranche(poolId, trancheId);
//         address vault = poolManager.deployVault(poolId, trancheId, address(erc20));
//         return vault;
//     }

//     function newErc20(string memory name, string memory symbol, uint8 decimals) internal returns (ERC20) {
//         ERC20 asset = new ERC20(decimals);
//         asset.file("name", name);
//         asset.file("symbol", symbol);
//         return asset;
//     }
// }
