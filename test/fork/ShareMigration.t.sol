// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.26;

import {Tranche} from "src/token/Tranche.sol";
import {Guardian} from "src/admin/Guardian.sol";
import {PermissionlessAdapter} from "test/mocks/PermissionlessAdapter.sol";
import {RestrictionUpdate} from "src/interfaces/token/IRestrictionManager.sol";
import {BytesLib} from "src/libraries/BytesLib.sol";
import {CastLib} from "src/libraries/CastLib.sol";
import {MathLib} from "src/libraries/MathLib.sol";
import {IInvestmentManager} from "src/interfaces/IInvestmentManager.sol";
import {Auth} from "src/Auth.sol";
import {MigrationSpell} from "src/spell/ShareMigrationDYFEVM.sol";
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
    Guardian guardianOld;
    Root rootOld;
    mapping(address => uint256) balancesOld;

    MigrationSpell spell;

    address self;

    function setUp() public virtual {
        self = address(this);

        spell = new MigrationSpell();

        _loadDeployment("mainnet", "ethereum-mainnet"); // Mainnet
        _loadFork(0);
        trancheTokenToMigrate = Tranche(address(spell.TRANCHE_TOKEN_OLD())); // Anemoy Liquid Treasury Fund 1 (LTF)
        guardianOld = Guardian(spell.GUARDIAN_OLD());
        rootOld = Root(spell.ROOT_OLD());

        deployNewContracts(); // Deploy Liquidity Pools v2
    }

    function testShareMigration() public {
        uint256 totalSupplyOld = 0;
        for (uint8 i; i < spell.getNumberOfMigratedMembers(); i++) {
            totalSupplyOld += trancheTokenToMigrate.balanceOf(spell.memberlistMembers(i));
        }
        // Check that total supply is accounted for
        assertEq(trancheTokenToMigrate.totalSupply(), totalSupplyOld);

        // get auth on old TrancheToken through DelayedAdmin - simulate governance
        vm.startPrank(spell.ADMIN_MULTISIG());
        guardianOld.scheduleRely(address(spell));
        // get auth on new TrancheToken through Guardian - simulate governance
        guardian.scheduleRely(address(spell));
        vm.stopPrank();
        // warp delay time = 48H & exec relies
        vm.warp(block.timestamp + 2 days);
        rootOld.executeScheduledRely(address(spell));
        root.executeScheduledRely(address(spell));

        
        for (uint8 i; i < spell.getNumberOfMigratedMembers(); i++) {
            if (spell.memberlistMembers(i) != spell.ESCROW_OLD()) {
                uint256 maxMint =
                    IInvestmentManager(spell.INVESTMENTMANAGER_OLD()).maxMint(spell.VAULT_OLD(), spell.memberlistMembers(i));
                balancesOld[spell.memberlistMembers(i)] =
                    trancheTokenToMigrate.balanceOf(spell.memberlistMembers(i)) + maxMint;
            }
        }

        spell.testCast(address(root), address(poolManager), address(restrictionManager));

        Tranche trancheToken = Tranche(address(poolManager.getTranche(spell.POOL_ID(), spell.TRANCHE_ID())));

        // check if all holders have been migrated correctly
        uint256 totalSupplyNew = 0;
        for (uint8 i; i < spell.getNumberOfMigratedMembers(); i++) {
            uint256 balanceNew = trancheToken.balanceOf(spell.memberlistMembers(i));
            totalSupplyNew += balanceNew;
            assertEq(trancheTokenToMigrate.balanceOf(spell.memberlistMembers(i)), 0);
            if (spell.memberlistMembers(i) != spell.ESCROW_OLD()) {
                assertEq(balanceNew, balancesOld[spell.memberlistMembers(i)]);
            }
        }
        assertEq(trancheTokenToMigrate.balanceOf(spell.ESCROW_OLD()), 0);
        
        // check total supply
        assertEq(trancheToken.totalSupply(), totalSupplyNew);
        assertEq(trancheToken.totalSupply(), totalSupplyOld);
        assertEq(trancheTokenToMigrate.totalSupply(), 0);

        // check trancheToken metadata
        assertEq(trancheTokenToMigrate.name(), spell.SYMBOL_OLD());
        assertEq(trancheTokenToMigrate.symbol(), spell.SYMBOL_OLD());
        assertEq(trancheToken.name(), spell.NAME());
        assertEq(trancheToken.symbol(), spell.SYMBOL());
        assertEq(trancheToken.decimals(), spell.DECIMALS());

        // assert denies
        assertEq(Auth(address(poolManager)).wards(address(spell)), 0);
        assertEq(Auth(address(trancheToken)).wards(address(spell)), 0);
        assertEq(Auth(address(trancheTokenToMigrate)).wards(address(spell)), 0);
        assertEq(Auth(spell.INVESTMENTMANAGER_OLD()).wards(address(spell)), 0);
        assertEq(Auth(address(rootOld)).wards(address(spell)), 0);
        assertEq(Auth(address(root)).wards(address(spell)), 0);
    }

    function deployNewContracts() internal {
        deploy(address(this));
        PermissionlessAdapter adapter = new PermissionlessAdapter(address(gateway));
        wire(address(adapter));
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
