// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.26;

import {Tranche} from "src/token/Tranche.sol";
import {Guardian} from "src/admin/Guardian.sol";
import {PermissionlessAdapter} from "test/mocks/PermissionlessAdapter.sol";
import {RestrictionUpdate} from "src/interfaces/token/IRestrictionManager.sol";
import {BytesLib} from "src/libraries/BytesLib.sol";
import {CastLib} from "src/libraries/CastLib.sol";
import {MathLib} from "src/libraries/MathLib.sol";
import "forge-std/Test.sol";
import "forge-std/StdJson.sol";
import "script/Deployer.sol";

interface TrancheTokenOld {
    function authTransferFrom(address from, address to, uint256 value) external returns (bool);
}

contract ForkTest is Deployer, Test {
    using BytesLib for bytes;
    using MathLib for uint256;
    using CastLib for *;
    using stdJson for string;

    string[] deployments;
    Tranche trancheTokenToMigrate;
    Tranche trancheToken;
    Guardian guardianOld;
    Root rootOld;

    address tokenToMigrate_ = 0x30baA3BA9D7089fD8D020a994Db75D14CF7eC83b;
    address guardianOld_ = 0x2559998026796Ca6fd057f3aa66F2d6ecdEd9028;
    address rootOld_ = 0x498016d30Cd5f0db50d7ACE329C07313a0420502;

    uint64 poolId = 4139607887;
    bytes16 trancheId = 0x97aa65f23e7be09fcd62d0554d2e9273;
    uint8 decimals = 6;
    string name = "Anemoy Liquid Treasury Fund 1";
    string symbol = "LTF";
    uint128 currencyId = 242333941209166991950178742833476896417; // USDC 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48
    address currency = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address adminMultiSig = 0xD9D30ab47c0f096b0AA67e9B8B1624504a63e7FD;
    // old lp 0xB3AC09cd5201569a821d87446A4aF1b202B10aFd

    address self;

    function setUp() public virtual {
        self = address(this);
        _loadDeployment("mainnet", "ethereum-mainnet"); // Mainnet
        _loadFork(0);
        trancheTokenToMigrate = Tranche(address(tokenToMigrate_)); // Anemoy Liquid Treasury Fund 1 (LTF)
        guardianOld = Guardian(address(guardianOld_));
        rootOld = Root(rootOld_);

        deployNewContracts(); // Deploy Liquidity Pools v2

        // _loadDeployment("mainnet", "base-mainnet");
        // _loadDeployment("mainnet", "arbitrum-mainnet");
        // _loadDeployment("mainnet", "celo-mainnet");
    }

    function testTrancheTokenMigration() public {
        address holder1 = 0x30d3bbAE8623d0e9C0db5c27B82dCDA39De40997;
        address holder2 = 0x2923c1B5313F7375fdaeE80b7745106deBC1b53E;
        address holder3 = 0xd595E1483c507E74E2E6A3dE8e7D08d8f6F74936;

        // load all holder balances and check whether they all add up to totalSupply
        uint256 holderBalance1 = trancheTokenToMigrate.balanceOf(holder1);
        uint256 holderBalance2 = trancheTokenToMigrate.balanceOf(holder2);
        uint256 holderBalance3 = trancheTokenToMigrate.balanceOf(holder3);
        assertEq((holderBalance1 + holderBalance2 + holderBalance3), trancheTokenToMigrate.totalSupply());

        // get auth on old TrancheToken through DelayedAdmin - simulate governance
        vm.startPrank(adminMultiSig);
        guardianOld.scheduleRely(self);
        // get auth on old TrancheToken through Guardian - simulate governance
        guardian.scheduleRely(self);
        vm.stopPrank();
        // warp delay time = 48H & exec relies
        vm.warp(block.timestamp + 2 days);
        rootOld.executeScheduledRely(self);
        root.executeScheduledRely(self);
        // exec auth relies
        rootOld.relyContract(address(trancheTokenToMigrate), self);
        root.relyContract(address(trancheToken), self);
        root.relyContract(address(poolManager), self);

        // // add holders to the allowlist of new token - simulate governance
        bytes memory update1 =
            abi.encodePacked(uint8(RestrictionUpdate.UpdateMember), address(holder1).toBytes32(), type(uint64).max);
        bytes memory update2 =
            abi.encodePacked(uint8(RestrictionUpdate.UpdateMember), address(holder2).toBytes32(), type(uint64).max);
        bytes memory update3 =
            abi.encodePacked(uint8(RestrictionUpdate.UpdateMember), address(holder3).toBytes32(), type(uint64).max);

        poolManager.updateRestriction(poolId, trancheId, update1);
        poolManager.updateRestriction(poolId, trancheId, update2);
        poolManager.updateRestriction(poolId, trancheId, update3);

        // mint new tranche Tokens to users and make sure the balance equals with old token balances
        trancheToken.mint(holder1, holderBalance1);
        trancheToken.mint(holder2, holderBalance2);
        trancheToken.mint(holder3, holderBalance3);

        assertEq(holderBalance1, trancheToken.balanceOf(holder1));
        assertEq(holderBalance2, trancheToken.balanceOf(holder2));
        assertEq(holderBalance3, trancheToken.balanceOf(holder3));
        assertEq(trancheTokenToMigrate.totalSupply(), trancheToken.totalSupply());

        // burn old tranche tokens using auth transfers
        TrancheTokenOld(tokenToMigrate_).authTransferFrom(holder1, self, holderBalance1);
        TrancheTokenOld(tokenToMigrate_).authTransferFrom(holder2, self, holderBalance2);
        TrancheTokenOld(tokenToMigrate_).authTransferFrom(holder3, self, holderBalance3);
        trancheTokenToMigrate.burn(self, holderBalance1);
        trancheTokenToMigrate.burn(self, holderBalance2);
        trancheTokenToMigrate.burn(self, holderBalance3);

        assertEq(trancheTokenToMigrate.balanceOf(holder1), 0);
        assertEq(trancheTokenToMigrate.balanceOf(holder2), 0);
        assertEq(trancheTokenToMigrate.balanceOf(holder3), 0);
        assertEq(trancheTokenToMigrate.totalSupply(), 0);

        // rename token
        trancheTokenToMigrate.file("name", "test");
        trancheTokenToMigrate.file("symbol", "test");
        assertEq(trancheTokenToMigrate.name(), "test");
        assertEq(trancheTokenToMigrate.symbol(), "test");
    }

    function deployNewContracts() internal {
        deploy(address(this));
        PermissionlessAdapter adapter = new PermissionlessAdapter(address(gateway));
        wire(address(adapter));

        // simulate tranche & pool deployments - test is ward on poolManager
        // deploy tranche token
        poolManager.addPool(poolId);
        poolManager.addTranche(poolId, trancheId, name, symbol, decimals, restrictionManager);
        trancheToken = Tranche(poolManager.deployTranche(poolId, trancheId));
        // deploy LiquidityPool
        poolManager.addAsset(currencyId, currency);
        poolManager.allowAsset(poolId, currencyId);
        poolManager.deployVault(poolId, trancheId, currency);
    }

    function _loadDeployment(string memory folder, string memory name) internal {
        deployments.push(vm.readFile(string.concat(vm.projectRoot(), "/deployments/", folder, "/", name, ".json")));
    }

    function _loadFork(uint256 id) internal {
        string memory rpcUrl = abi.decode(deployments[id].parseRaw(".rpcUrl"), (string));
        uint256 forkId = vm.createFork(rpcUrl);
        vm.selectFork(forkId);
    }

    function _get(uint256 id, string memory key) internal view returns (address) {
        return abi.decode(deployments[id].parseRaw(key), (address));
    }
}
