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
import {MigrationSpell} from "src/spell/ShareMigration_LTF_Celo.sol";
import "forge-std/Test.sol";
import "forge-std/StdJson.sol";
import "script/Deployer.sol";

interface IVaultOld {
    function poolId() external view returns (uint64);
    function trancheId() external view returns (bytes16);
    function share() external view returns (address);
    function manager() external view returns (address);
    function escrow() external view returns (address);
    function asset() external view returns (address);
}

interface TrancheTokenOld {
    function authTransferFrom(address from, address to, uint256 value) external returns (bool);
}

contract TestableSpell is MigrationSpell {
    function testCast(address root, address poolManager, address restrictionManager) public {
        require(!done, "spell-already-cast");
        done = true;
        ROOT_NEW = root;
        POOLMANAGER_NEW = poolManager;
        RESTRICTIONMANAGER_NEW = restrictionManager;
        execute();
    }
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

    TestableSpell spell;

    address self;

    function setUp() public virtual {
        self = address(this);

        spell = new TestableSpell();

        _loadDeployment("mainnet", spell.NETWORK());
        _loadFork(0);
        IVaultOld vaultOld = IVaultOld(spell.VAULT_OLD());
        trancheTokenToMigrate = Tranche(vaultOld.share());
        guardianOld = Guardian(spell.GUARDIAN_OLD());
        rootOld = Root(spell.ROOT_OLD());
    }

    function testShareMigrationAgainstRealDeployment() public {
        guardian = Guardian(spell.GUARDIAN_NEW());
        root = Root(spell.ROOT_NEW());
        migrateShares(spell.ROOT_NEW(), spell.POOLMANAGER_NEW(), spell.RESTRICTIONMANAGER_NEW(), spell.ADMIN_MULTISIG());
    }

    function testShareMigrationAgainstMockDeployment() public {
        deployNewContracts(); // Deploy Liquidity Pools v2
        migrateShares(
            address(root), address(poolManager), address(restrictionManager), 0xD9D30ab47c0f096b0AA67e9B8B1624504a63e7FD
        );
    }

    function migrateShares(address root, address poolManager, address restrictionManager, address adminMultisig)
        internal
    {
        uint256 totalSupplyOld = 0;
        for (uint8 i; i < spell.getNumberOfMigratedMembers(); i++) {
            totalSupplyOld += trancheTokenToMigrate.balanceOf(spell.memberlistMembers(i));
        }
        // Check that total supply is accounted for
        assertEq(trancheTokenToMigrate.totalSupply(), totalSupplyOld);

        // get auth on old TrancheToken through DelayedAdmin - simulate governance
        vm.prank(spell.ADMIN_MULTISIG());
        guardianOld.scheduleRely(address(spell));
        // get auth on new TrancheToken through Guardian - simulate governance
        // Deployer.sol always sets adminSafe to the EVM multisig, so we override the spell's multisig here during mock
        // deployments
        vm.prank(adminMultisig);
        guardian.scheduleRely(address(spell));
        // warp delay time = 48H & exec relies
        vm.warp(block.timestamp + 2 days);
        rootOld.executeScheduledRely(address(spell));
        Root(root).executeScheduledRely(address(spell));

        IVaultOld vaultOld = IVaultOld(spell.VAULT_OLD());
        uint64 poolId = vaultOld.poolId();
        bytes16 trancheId = vaultOld.trancheId();

        for (uint8 i; i < spell.getNumberOfMigratedMembers(); i++) {
            if (spell.memberlistMembers(i) != vaultOld.escrow()) {
                uint256 maxMint =
                    IInvestmentManager(vaultOld.manager()).maxMint(spell.VAULT_OLD(), spell.memberlistMembers(i));
                balancesOld[spell.memberlistMembers(i)] =
                    trancheTokenToMigrate.balanceOf(spell.memberlistMembers(i)) + maxMint;
            }
        }

        spell.testCast(address(root), address(poolManager), address(restrictionManager));

        Tranche trancheToken = Tranche(address(PoolManager(poolManager).getTranche(poolId, trancheId)));

        // check if all holders have been migrated correctly
        uint256 totalSupplyNew = 0;
        for (uint8 i; i < spell.getNumberOfMigratedMembers(); i++) {
            uint256 balanceNew = trancheToken.balanceOf(spell.memberlistMembers(i));
            totalSupplyNew += balanceNew;
            assertApproxEqAbs(trancheTokenToMigrate.balanceOf(spell.memberlistMembers(i)), 0, 1);
            if (spell.memberlistMembers(i) != vaultOld.escrow()) {
                assertApproxEqAbs(balanceNew, balancesOld[spell.memberlistMembers(i)], 1);
            }
        }
        assertApproxEqAbs(trancheTokenToMigrate.balanceOf(vaultOld.escrow()), 0, 1);

        // check total supply
        assertApproxEqAbs(trancheToken.totalSupply(), totalSupplyNew, 1);
        assertApproxEqAbs(trancheToken.totalSupply(), totalSupplyOld, 1);
        assertApproxEqAbs(trancheTokenToMigrate.totalSupply(), 0, 1);

        // check trancheToken metadata
        assertEq(trancheTokenToMigrate.name(), spell.NAME_OLD());
        assertEq(trancheTokenToMigrate.symbol(), spell.SYMBOL_OLD());
        assertEq(trancheToken.name(), spell.NAME());
        assertEq(trancheToken.symbol(), spell.SYMBOL());
        assertEq(trancheToken.decimals(), trancheTokenToMigrate.decimals());

        // assert denies
        assertEq(Auth(address(poolManager)).wards(address(spell)), 0);
        assertEq(Auth(address(trancheToken)).wards(address(spell)), 0);
        assertEq(Auth(address(trancheTokenToMigrate)).wards(address(spell)), 0);
        assertEq(Auth(vaultOld.manager()).wards(address(spell)), 0);
        assertEq(Auth(address(rootOld)).wards(address(spell)), 0);
        assertEq(Auth(address(root)).wards(address(spell)), 0);

        // assert vault was deployed
        assertTrue(PoolManager(poolManager).getVault(poolId, trancheId, vaultOld.asset()) != address(0));
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
