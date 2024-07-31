// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.26;

import {Tranche} from "src/token/Tranche.sol";
import {Guardian} from "src/admin/Guardian.sol";
import {PermissionlessAdapter} from "test/mocks/PermissionlessAdapter.sol";
import {RestrictionUpdate} from "src/interfaces/token/IRestrictionManager.sol";
import {BytesLib} from "src/libraries/BytesLib.sol";
import {CastLib} from "src/libraries/CastLib.sol";
import {MathLib} from "src/libraries/MathLib.sol";
import {MigrationSpell} from "src/spell/MigrationSpell-mainnet.sol";
import {IInvestmentManager} from "src/interfaces/IInvestmentManager.sol";
import {Auth} from "src/Auth.sol";
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

    address adminMultiSig = 0xD9D30ab47c0f096b0AA67e9B8B1624504a63e7FD;

    MigrationSpell spell;

    address self;

    function setUp() public virtual {
        self = address(this);

        spell = new MigrationSpell();

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
        uint256 totalSupply = 0;
        for (uint8 i; i < spell.getNumberOfMigratedMembers(); i++) {
            totalSupply += trancheTokenToMigrate.balanceOf(spell.memberlistMembers(i));
        }
        assertEq(trancheTokenToMigrate.totalSupply(), totalSupply);

        // get auth on old TrancheToken through DelayedAdmin - simulate governance
        vm.startPrank(adminMultiSig);
        guardianOld.scheduleRely(self);
        // get auth on new TrancheToken through Guardian - simulate governance
        guardian.scheduleRely(self);
        vm.stopPrank();
        // warp delay time = 48H & exec relies
        vm.warp(block.timestamp + 2 days);
        rootOld.executeScheduledRely(self);
        root.executeScheduledRely(self);
        // exec auth relies
        rootOld.relyContract(address(trancheTokenToMigrate), self);
        rootOld.relyContract(spell.INVESTMENTMANAGER_OLD(), self);
        root.relyContract(address(trancheToken), self);
        root.relyContract(address(poolManager), self);

        // add holders to the allowlist of new token - simulate governance
        for (uint8 i; i < spell.getNumberOfMigratedMembers(); i++) {
            bytes memory update = abi.encodePacked(
                uint8(RestrictionUpdate.UpdateMember),
                spell.memberlistMembers(i).toBytes32(),
                spell.validUntil(spell.memberlistMembers(i))
            );
            poolManager.updateRestriction(spell.POOL_ID(), spell.TRANCHE_ID(), update);

            uint256 escrowBalance = trancheTokenToMigrate.balanceOf(spell.ESCROW_OLD());
            if (escrowBalance > 0) {
                uint256 maxMint = IInvestmentManager(spell.INVESTMENTMANAGER_OLD()).maxMint(
                    spell.VAULT_OLD(), spell.memberlistMembers(i)
                );
                if (maxMint > 0) {
                    IInvestmentManager(spell.INVESTMENTMANAGER_OLD()).mint(
                        spell.VAULT_OLD(), maxMint, spell.memberlistMembers(i), spell.memberlistMembers(i)
                    );
                }
            }
            uint256 holderBalance = trancheTokenToMigrate.balanceOf(spell.memberlistMembers(i));
            if (holderBalance > 0) {
                trancheToken.mint(spell.memberlistMembers(i), holderBalance);
                assertEq(trancheToken.balanceOf(spell.memberlistMembers(i)), holderBalance);
                TrancheTokenOld(address(trancheTokenToMigrate)).authTransferFrom(
                    spell.memberlistMembers(i), self, holderBalance
                );
            }
        }

        // check if all holders have been migrated correctly
        uint256 totalSupplyNew = 0;
        for (uint8 i; i < spell.getNumberOfMigratedMembers(); i++) {
            uint256 balanceNew = trancheToken.balanceOf(spell.memberlistMembers(i));
            totalSupplyNew += balanceNew;
            assertEq(trancheTokenToMigrate.balanceOf(spell.memberlistMembers(i)), 0);
        }
        assertEq(trancheTokenToMigrate.balanceOf(spell.ESCROW_OLD()), 0);
        assertEq(trancheToken.totalSupply(), totalSupplyNew);
        assertEq(trancheTokenToMigrate.totalSupply(), trancheToken.totalSupply());

        // burn old tranche tokens using auth transfers & make sure old tranche token supply equals zero
        for (uint8 i; i < spell.getNumberOfMigratedMembers(); i++) {
            uint256 balance = trancheTokenToMigrate.balanceOf(spell.memberlistMembers(i));
            if (balance > 0) {
                TrancheTokenOld(tokenToMigrate_).authTransferFrom(spell.memberlistMembers(i), self, balance);
            }
            assertEq(trancheTokenToMigrate.balanceOf(spell.memberlistMembers(i)), 0);
        }
        uint256 balance = trancheTokenToMigrate.balanceOf(self);
        trancheTokenToMigrate.burn(self, balance);

        assertEq(trancheTokenToMigrate.totalSupply(), 0);

        // rename old tranche token
        trancheTokenToMigrate.file("name", spell.NAME_OLD());
        trancheTokenToMigrate.file("symbol", spell.SYMBOL_OLD());
        assertEq(trancheTokenToMigrate.name(), spell.SYMBOL_OLD());
        assertEq(trancheTokenToMigrate.symbol(), spell.SYMBOL_OLD());

        // assert new trancheToken metadata
        assertEq(trancheToken.name(), spell.NAME());
        assertEq(trancheToken.symbol(), spell.SYMBOL());
        assertEq(trancheToken.decimals(), spell.DECIMALS());

        // deny contracts
        rootOld.denyContract(address(trancheTokenToMigrate), self);
        rootOld.denyContract(spell.INVESTMENTMANAGER_OLD(), self);
        root.denyContract(address(trancheToken), self);

        root.denyContract(address(poolManager), self);
        // assert denies
        assertEq(Auth(address(poolManager)).wards(address(spell)), 0);
        assertEq(Auth(address(trancheToken)).wards(address(spell)), 0);
        assertEq(Auth(spell.INVESTMENTMANAGER_OLD()).wards(address(spell)), 0);
        assertEq(Auth(address(rootOld)).wards(address(spell)), 0);

    }

    function deployNewContracts() internal {
        deploy(address(this));
        PermissionlessAdapter adapter = new PermissionlessAdapter(address(gateway));
        wire(address(adapter));

        // simulate tranche & pool deployments - test is ward on poolManager
        // deploy tranche token
        poolManager.addPool(spell.POOL_ID());
        poolManager.addTranche(
            spell.POOL_ID(), spell.TRANCHE_ID(), spell.NAME(), spell.SYMBOL(), spell.DECIMALS(), restrictionManager
        );
        trancheToken = Tranche(poolManager.deployTranche(spell.POOL_ID(), spell.TRANCHE_ID()));

        poolManager.addAsset(spell.CURRENCY_ID(), spell.CURRENCY());
        poolManager.allowAsset(spell.POOL_ID(), spell.CURRENCY_ID());
        poolManager.deployVault(spell.POOL_ID(), spell.TRANCHE_ID(), spell.CURRENCY());
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
