// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.26;

import {InvestmentManager} from "src/InvestmentManager.sol";
import {Gateway} from "src/gateway/Gateway.sol";
import {MockCentrifugeChain} from "test/mocks/MockCentrifugeChain.sol";
import {Escrow} from "src/Escrow.sol";
import {Guardian} from "src/admin/Guardian.sol";
import {MockAdapter} from "test/mocks/MockAdapter.sol";
import {PoolManager, Pool} from "src/PoolManager.sol";
import {ERC20} from "src/token/ERC20.sol";
import {Tranche} from "src/token/Tranche.sol";
import {ERC7540VaultTest} from "test/unit/ERC7540Vault.t.sol";
import {PermissionlessAdapter} from "test/mocks/PermissionlessAdapter.sol";
import {Root} from "src/Root.sol";
import {ERC7540Vault} from "src/ERC7540Vault.sol";
import {AxelarScript} from "script/Axelar.s.sol";
import "script/Deployer.sol";
import "src/libraries/MathLib.sol";
import "forge-std/Test.sol";

interface ApproveLike {
    function approve(address, uint256) external;
}

interface WardLike {
    function wards(address who) external returns (uint256);
}

interface HookLike {
    function updateMember(address user, uint64 validUntil) external;
}

contract DeployTest is Test, Deployer {
    using MathLib for uint256;

    uint8 constant PRICE_DECIMALS = 18;
    address deployer;
    PermissionlessAdapter adapter;
    address[] accounts;
    Guardian fakeGuardian;

    function setUp() public {
        deployer = address(this);
        deploy(deployer);
        adapter = new PermissionlessAdapter(address(gateway));
        wire(address(adapter));

        // overwrite deployed guardian with a new mock safe guardian
        accounts = new address[](3);
        accounts[0] = makeAddr("account1");
        accounts[1] = makeAddr("account2");
        accounts[2] = makeAddr("account3");
        adminSafe = address(new MockSafe(accounts, 1));
        fakeGuardian = new Guardian(adminSafe, address(root), address(gateway));

        removeDeployerAccess(address(adapter), address(this));
    }

    function testDeployerHasNoAccess() public {
        vm.expectRevert("Auth/not-authorized");
        root.relyContract(address(investmentManager), address(1));

        // checking in the same order as they are deployed
        assertEq(escrow.wards(deployer), 0);
        assertEq(routerEscrow.wards(deployer), 0);
        assertEq(root.wards(deployer), 0);
        assertEq(WardLike(vaultFactory).wards(deployer), 0);
        assertEq(WardLike(restrictionManager).wards(deployer), 0);
        assertEq(WardLike(trancheFactory).wards(deployer), 0);
        assertEq(investmentManager.wards(deployer), 0);
        assertEq(poolManager.wards(deployer), 0);
        assertEq(gasService.wards(deployer), 0);
        assertEq(gateway.wards(deployer), 0);
        assertEq(adapter.wards(deployer), 0);
    }

    function testAdminSetup(address nonAdmin, address nonPauser) public {
        vm.assume(nonAdmin != adminSafe);
        vm.assume(nonPauser != accounts[0] && nonPauser != accounts[1] && nonPauser != accounts[2]);

        assertEq(address(fakeGuardian.safe()), adminSafe);
        for (uint256 i = 0; i < accounts.length; i++) {
            assertEq(MockSafe(adminSafe).isOwner(accounts[i]), true);
        }
        assertEq(MockSafe(adminSafe).isOwner(nonPauser), false);
    }

    function testAccessRightsAssignment() public {
        address poolManager_ = address(poolManager);
        address root_ = address(root);
        address gateway_ = address(gateway);
        address guardian_ = address(guardian);

        assertEq(gasService.wards(poolManager_), 1);
        assertEq(escrow.wards(poolManager_), 1);
        assertEq(WardLike(vaultFactory).wards(poolManager_), 1);
        assertEq(WardLike(restrictionManager).wards(poolManager_), 1);
        assertEq(WardLike(trancheFactory).wards(poolManager_), 1);

        assertEq(router.wards(root_), 1);
        assertEq(poolManager.wards(root_), 1);
        assertEq(investmentManager.wards(root_), 1);
        assertEq(gateway.wards(root_), 1);
        assertEq(gasService.wards(root_), 1);
        assertEq(escrow.wards(root_), 1);
        assertEq(routerEscrow.wards(root_), 1);
        assertEq(adapter.wards(root_), 1);
        assertEq(WardLike(vaultFactory).wards(root_), 1);
        assertEq(WardLike(restrictionManager).wards(root_), 1);
        assertEq(WardLike(trancheFactory).wards(root_), 1);

        assertEq(root.wards(gateway_), 1);
        assertEq(poolManager.wards(gateway_), 1);
        assertEq(investmentManager.wards(gateway_), 1);

        assertEq(gateway.wards(guardian_), 1);
        assertEq(root.wards(guardian_), 1);

        assertEq(routerEscrow.wards(address(router)), 1);
        assertEq(investmentManager.wards(vaultFactory), 1);
    }

    function testFilings() public {
        assertEq(poolManager.investmentManager(), address(investmentManager));
        assertEq(address(poolManager.gateway()), address(gateway));
        assertEq(address(poolManager.gasService()), address(gasService));

        assertEq(address(investmentManager.poolManager()), address(poolManager));
        assertEq(address(investmentManager.gateway()), address(gateway));

        assertEq(gateway.adapters(0), address(adapter));
    }

    function testEndorsements() public {
        assertTrue(root.endorsed(address(escrow)));
        assertTrue(root.endorsed(address(router)));
    }

    // deal(address(erc20), self, amount);
    // deal(address(gateway), 10 ether);

    //         deal(address(erc20), self, amount);

    //         vm.prank(address(gateway));
    //         HookLike(tranche.hook()).updateMember(self, validUntil);

    //         depositMint(poolId, trancheId, price, amount, vault);
    //         amount = tranche.balanceOf(self);

    //         redeemWithdraw(poolId, trancheId, price, amount, vault);
    //     }

    //     function depositMint(uint64 poolId, bytes16 trancheId, uint128 price, uint256 amount, ERC7540Vault vault)
    // public
    // {
    //         erc20.approve(address(vault), amount); // add allowance
    //         vault.requestDeposit(amount, self, self, "");

    //         // ensure funds are locked in escrow
    //         assertEq(erc20.balanceOf(address(escrow)), amount);
    //         assertEq(erc20.balanceOf(self), 0);

    //         // trigger executed collectInvest
    //         uint128 _assetId = poolManager.assetToId(address(erc20)); // retrieve assetId

    //         Tranche tranche = Tranche(address(vault.share()));
    //         uint128 shares = (
    //             amount.mulDiv(
    //                 10 ** (PRICE_DECIMALS - erc20.decimals() + tranche.decimals()), price, MathLib.Rounding.Down
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

    //         assertEq(tranche.balanceOf(self), shares / div);
    //         assertEq(tranche.balanceOf(address(escrow)), shares - shares / div);
    //         assertEq(vault.maxMint(self), shares - shares / div);
    //         assertEq(vault.maxDeposit(self), amount - amount / div); // max deposit

    //         vault.mint(vault.maxMint(self), self);

    //         assertEq(tranche.balanceOf(self), shares);
    //         assertTrue(tranche.balanceOf(address(escrow)) <= 1);
    //         assertTrue(vault.maxMint(self) <= 1);
    //     }

    //     function redeemWithdraw(uint64 poolId, bytes16 trancheId, uint128 price, uint256 amount, ERC7540Vault vault)
    //         public
    //     {
    //         vault.requestRedeem(amount, address(this), address(this), "");

    //         // redeem
    //         Tranche tranche = Tranche(address(vault.share()));
    //         uint128 _assetId = poolManager.assetToId(address(erc20)); // retrieve assetId
    //         uint128 assets = (
    //             amount.mulDiv(price, 10 ** (18 - erc20.decimals() + tranche.decimals()), MathLib.Rounding.Down)
    //         ).toUint128();
    //         // Assume an epoch execution happens on cent chain
    //         // Assume a bot calls collectRedeem for this user on cent chain
    //         vm.prank(address(gateway));
    //         investmentManager.fulfillRedeemRequest(poolId, trancheId, self, _assetId, assets, uint128(amount));

    //         assertEq(vault.maxWithdraw(self), assets);
    //         assertEq(vault.maxRedeem(self), amount);
    //         assertEq(tranche.balanceOf(address(escrow)), 0);

    //         uint128 div = 2;
    //         vault.redeem(amount / div, self, self);
    //         assertEq(tranche.balanceOf(self), 0);
    //         assertEq(tranche.balanceOf(address(escrow)), 0);
    //         assertEq(erc20.balanceOf(self), assets / div);
    //         assertEq(vault.maxWithdraw(self), assets / div);
    //         assertEq(vault.maxRedeem(self), amount / div);

    //         vault.withdraw(vault.maxWithdraw(self), self, self);
    //         assertEq(tranche.balanceOf(self), 0);
    //         assertEq(tranche.balanceOf(address(escrow)), 0);
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
}
