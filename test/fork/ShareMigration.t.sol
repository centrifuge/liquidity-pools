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
import {MigrationSpell as LTF_EVM} from "src/spell/ShareMigration_LTF_EVM.sol";
import {MigrationSpell as DYF_EVM} from "src/spell/ShareMigration_DYF_EVM.sol";
import {MigrationSpell as NS3SR_EVM} from "src/spell/ShareMigration_NS3SR_EVM.sol";
import {MigrationSpell as NS3JR_EVM} from "src/spell/ShareMigration_NS3JR_EVM.sol";
import {MigrationSpell as LTF_Base} from "src/spell/ShareMigration_LTF_Base.sol";
import {MigrationSpell as LTF_Celo} from "src/spell/ShareMigration_LTF_Celo.sol";
import {MigrationSpellBase} from "src/spell/MigrationSpellBase.sol";
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

contract TestableSpell is MigrationSpellBase {
    constructor(MigrationSpellBase _baseSpell) {
        // Copy all the properties from the base spell
        NETWORK = _baseSpell.NETWORK();
        ROOT_OLD = _baseSpell.ROOT_OLD();
        ADMIN_MULTISIG = _baseSpell.ADMIN_MULTISIG();
        GUARDIAN_OLD = _baseSpell.GUARDIAN_OLD();
        VAULT_OLD = _baseSpell.VAULT_OLD();
        ROOT_NEW = _baseSpell.ROOT_NEW();
        GUARDIAN_NEW = _baseSpell.GUARDIAN_NEW();
        POOLMANAGER_NEW = _baseSpell.POOLMANAGER_NEW();
        RESTRICTIONMANAGER_NEW = _baseSpell.RESTRICTIONMANAGER_NEW();
        NAME = _baseSpell.NAME();
        SYMBOL = _baseSpell.SYMBOL();
        NAME_OLD = _baseSpell.NAME_OLD();
        SYMBOL_OLD = _baseSpell.SYMBOL_OLD();

        uint256 memberCount = _baseSpell.getNumberOfMigratedMembers();
        for (uint256 i = 0; i < memberCount; i++) {
            address member = _baseSpell.memberlistMembers(i);
            memberlistMembers.push(member);
            validUntil[member] = _baseSpell.validUntil(member);
        }
    }

    function testCast(address root, address poolManager, address restrictionManager) public {
        ROOT_NEW = root;
        POOLMANAGER_NEW = poolManager;
        RESTRICTIONMANAGER_NEW = restrictionManager;
        executePartOne();
        executePartTwo();
    }

    function testCastPartOne(address root, address poolManager, address restrictionManager) public {
        ROOT_NEW = root;
        POOLMANAGER_NEW = poolManager;
        RESTRICTIONMANAGER_NEW = restrictionManager;
        executePartOne();
    }

    function testCastPartTwo(address root, address poolManager, address restrictionManager) public {
        ROOT_NEW = root;
        POOLMANAGER_NEW = poolManager;
        RESTRICTIONMANAGER_NEW = restrictionManager;
        executePartTwo();
    }
}

contract ForkTest is Deployer, Test {
    using BytesLib for bytes;
    using MathLib for uint256;
    using CastLib for *;
    using stdJson for string;

    address self;
    mapping(address => mapping(address => uint256)) balancesOld; // member => token => balance
    string[] deployments;

    struct MigrationContext {
        TestableSpell spell;
        IVaultOld vaultOld;
        Tranche trancheTokenToMigrate;
        Tranche trancheToken;
        uint64 poolId;
        bytes16 trancheId;
        uint256 totalSupplyOld;
        uint256 totalSupplyNew;
    }

    function setUp() public virtual {
        self = address(this);
    }

    function test_LTF_EVM_MigrationAgainstRealDeployment() public {
        TestableSpell spell = new TestableSpell(new LTF_EVM());
        _loadDeployment("mainnet", spell.NETWORK());
        _loadFork(0);
        MigrationContext memory ctx = migrateSharesPartOne(
            spell,
            spell.ROOT_NEW(),
            spell.POOLMANAGER_NEW(),
            spell.RESTRICTIONMANAGER_NEW(),
            spell.ADMIN_MULTISIG(),
            spell.GUARDIAN_NEW()
        );
        migrateSharesPartTwo(ctx, spell.ROOT_NEW(), spell.POOLMANAGER_NEW(), spell.RESTRICTIONMANAGER_NEW());
    }

    function test_LTF_EVM_MigrationAgainstMockDeployment() public {
        TestableSpell spell = new TestableSpell(new LTF_EVM());
        _loadDeployment("mainnet", spell.NETWORK());
        _loadFork(0);
        deployNewContracts();
        MigrationContext memory ctx = migrateSharesPartOne(
            spell,
            address(root),
            address(poolManager),
            address(restrictionManager),
            0xD9D30ab47c0f096b0AA67e9B8B1624504a63e7FD,
            address(guardian)
        );
        migrateSharesPartTwo(ctx, address(root), address(poolManager), address(restrictionManager));
    }

    function test_DYF_EVM_MigrationAgainstRealDeployment() public {
        TestableSpell spell = new TestableSpell(new DYF_EVM());
        _loadDeployment("mainnet", spell.NETWORK());
        _loadFork(0);
        MigrationContext memory ctx = migrateSharesPartOne(
            spell,
            spell.ROOT_NEW(),
            spell.POOLMANAGER_NEW(),
            spell.RESTRICTIONMANAGER_NEW(),
            spell.ADMIN_MULTISIG(),
            spell.GUARDIAN_NEW()
        );
        migrateSharesPartTwo(ctx, spell.ROOT_NEW(), spell.POOLMANAGER_NEW(), spell.RESTRICTIONMANAGER_NEW());
    }

    function test_DYF_EVM_MigrationAgainstMockDeployment() public {
        TestableSpell spell = new TestableSpell(new DYF_EVM());
        _loadDeployment("mainnet", spell.NETWORK());
        _loadFork(0);
        deployNewContracts();
        MigrationContext memory ctx = migrateSharesPartOne(
            spell,
            address(root),
            address(poolManager),
            address(restrictionManager),
            0xD9D30ab47c0f096b0AA67e9B8B1624504a63e7FD,
            address(guardian)
        );
        migrateSharesPartTwo(ctx, address(root), address(poolManager), address(restrictionManager));
    }

    function test_NS3SR_EVM_MigrationAgainstRealDeployment() public {
        TestableSpell spell = new TestableSpell(new NS3SR_EVM());
        _loadDeployment("mainnet", spell.NETWORK());
        _loadFork(0);
        MigrationContext memory ctx = migrateSharesPartOne(
            spell,
            spell.ROOT_NEW(),
            spell.POOLMANAGER_NEW(),
            spell.RESTRICTIONMANAGER_NEW(),
            spell.ADMIN_MULTISIG(),
            spell.GUARDIAN_NEW()
        );
        migrateSharesPartTwo(ctx, spell.ROOT_NEW(), spell.POOLMANAGER_NEW(), spell.RESTRICTIONMANAGER_NEW());
    }

    function test_NS3SR_EVM_MigrationAgainstMockDeployment() public {
        TestableSpell spell = new TestableSpell(new NS3SR_EVM());
        _loadDeployment("mainnet", spell.NETWORK());
        _loadFork(0);
        deployNewContracts();
        MigrationContext memory ctx = migrateSharesPartOne(
            spell,
            address(root),
            address(poolManager),
            address(restrictionManager),
            0xD9D30ab47c0f096b0AA67e9B8B1624504a63e7FD,
            address(guardian)
        );
        migrateSharesPartTwo(ctx, address(root), address(poolManager), address(restrictionManager));
    }

    function test_NS3JR_EVM_MigrationAgainstRealDeployment() public {
        TestableSpell spell = new TestableSpell(new NS3JR_EVM());
        _loadDeployment("mainnet", spell.NETWORK());
        _loadFork(0);
        MigrationContext memory ctx = migrateSharesPartOne(
            spell,
            spell.ROOT_NEW(),
            spell.POOLMANAGER_NEW(),
            spell.RESTRICTIONMANAGER_NEW(),
            spell.ADMIN_MULTISIG(),
            spell.GUARDIAN_NEW()
        );
        migrateSharesPartTwo(ctx, spell.ROOT_NEW(), spell.POOLMANAGER_NEW(), spell.RESTRICTIONMANAGER_NEW());
    }

    function test_NS3JR_EVM_MigrationAgainstMockDeployment() public {
        TestableSpell spell = new TestableSpell(new NS3JR_EVM());
        _loadDeployment("mainnet", spell.NETWORK());
        _loadFork(0);
        deployNewContracts();
        MigrationContext memory ctx = migrateSharesPartOne(
            spell,
            address(root),
            address(poolManager),
            address(restrictionManager),
            0xD9D30ab47c0f096b0AA67e9B8B1624504a63e7FD,
            address(guardian)
        );
        migrateSharesPartTwo(ctx, address(root), address(poolManager), address(restrictionManager));
    }

    function test_LTF_Base_MigrationAgainstRealDeployment() public {
        TestableSpell spell = new TestableSpell(new LTF_Base());
        _loadDeployment("mainnet", spell.NETWORK());
        _loadFork(0);
        MigrationContext memory ctx = migrateSharesPartOne(
            spell,
            spell.ROOT_NEW(),
            spell.POOLMANAGER_NEW(),
            spell.RESTRICTIONMANAGER_NEW(),
            spell.ADMIN_MULTISIG(),
            spell.GUARDIAN_NEW()
        );
        migrateSharesPartTwo(ctx, spell.ROOT_NEW(), spell.POOLMANAGER_NEW(), spell.RESTRICTIONMANAGER_NEW());
    }

    function test_LTF_Base_MigrationAgainstMockDeployment() public {
        TestableSpell spell = new TestableSpell(new LTF_Base());
        _loadDeployment("mainnet", spell.NETWORK());
        _loadFork(0);
        deployNewContracts();
        MigrationContext memory ctx = migrateSharesPartOne(
            spell,
            address(root),
            address(poolManager),
            address(restrictionManager),
            0xD9D30ab47c0f096b0AA67e9B8B1624504a63e7FD,
            address(guardian)
        );
        migrateSharesPartTwo(ctx, address(root), address(poolManager), address(restrictionManager));
    }

    function test_LTF_Celo_MigrationAgainstRealDeployment() public {
        TestableSpell spell = new TestableSpell(new LTF_Celo());
        _loadDeployment("mainnet", spell.NETWORK());
        _loadFork(0);
        MigrationContext memory ctx = migrateSharesPartOne(
            spell,
            spell.ROOT_NEW(),
            spell.POOLMANAGER_NEW(),
            spell.RESTRICTIONMANAGER_NEW(),
            spell.ADMIN_MULTISIG(),
            spell.GUARDIAN_NEW()
        );
        migrateSharesPartTwo(ctx, spell.ROOT_NEW(), spell.POOLMANAGER_NEW(), spell.RESTRICTIONMANAGER_NEW());
    }

    function test_LTF_Celo_MigrationAgainstMockDeployment() public {
        TestableSpell spell = new TestableSpell(new LTF_Celo());
        _loadDeployment("mainnet", spell.NETWORK());
        _loadFork(0);
        deployNewContracts();
        MigrationContext memory ctx = migrateSharesPartOne(
            spell,
            address(root),
            address(poolManager),
            address(restrictionManager),
            0xD9D30ab47c0f096b0AA67e9B8B1624504a63e7FD,
            address(guardian)
        );
        migrateSharesPartTwo(ctx, address(root), address(poolManager), address(restrictionManager));
    }

    function testAllEVMMigrationsAgainstRealDeployment() public {
        TestableSpell spellLTF = new TestableSpell(new LTF_EVM());
        _loadDeployment("mainnet", spellLTF.NETWORK());
        _loadFork(0);
        MigrationContext memory ctxLTF = migrateSharesPartOne(
            spellLTF,
            spellLTF.ROOT_NEW(),
            spellLTF.POOLMANAGER_NEW(),
            spellLTF.RESTRICTIONMANAGER_NEW(),
            spellLTF.ADMIN_MULTISIG(),
            spellLTF.GUARDIAN_NEW()
        );
        TestableSpell spellDYF = new TestableSpell(new DYF_EVM());
        MigrationContext memory ctxDYF = migrateSharesPartOne(
            spellDYF,
            spellDYF.ROOT_NEW(),
            spellDYF.POOLMANAGER_NEW(),
            spellDYF.RESTRICTIONMANAGER_NEW(),
            spellDYF.ADMIN_MULTISIG(),
            spellDYF.GUARDIAN_NEW()
        );
        TestableSpell spellNS3SR = new TestableSpell(new NS3SR_EVM());
        MigrationContext memory ctxNS3SR = migrateSharesPartOne(
            spellNS3SR,
            spellNS3SR.ROOT_NEW(),
            spellNS3SR.POOLMANAGER_NEW(),
            spellNS3SR.RESTRICTIONMANAGER_NEW(),
            spellNS3SR.ADMIN_MULTISIG(),
            spellNS3SR.GUARDIAN_NEW()
        );
        TestableSpell spellNS3JR = new TestableSpell(new NS3JR_EVM());
        MigrationContext memory ctxNS3JR = migrateSharesPartOne(
            spellNS3JR,
            spellNS3JR.ROOT_NEW(),
            spellNS3JR.POOLMANAGER_NEW(),
            spellNS3JR.RESTRICTIONMANAGER_NEW(),
            spellNS3JR.ADMIN_MULTISIG(),
            spellNS3JR.GUARDIAN_NEW()
        );
        migrateSharesPartTwo(
            ctxLTF,
            spellLTF.ROOT_NEW(),
            spellLTF.POOLMANAGER_NEW(),
            spellLTF.RESTRICTIONMANAGER_NEW()
        );
        migrateSharesPartTwo(
            ctxDYF,
            spellDYF.ROOT_NEW(),
            spellDYF.POOLMANAGER_NEW(),
            spellDYF.RESTRICTIONMANAGER_NEW()
        );
        migrateSharesPartTwo(
            ctxNS3SR,
            spellNS3SR.ROOT_NEW(),
            spellNS3SR.POOLMANAGER_NEW(),
            spellNS3SR.RESTRICTIONMANAGER_NEW()
        );
        migrateSharesPartTwo(
            ctxNS3JR,
            spellNS3JR.ROOT_NEW(),
            spellNS3JR.POOLMANAGER_NEW(),
            spellNS3JR.RESTRICTIONMANAGER_NEW()
        );
    }

    function migrateSharesPartOne(
        TestableSpell spell,
        address root,
        address poolManager,
        address restrictionManager,
        address adminMultisig,
        address guardian
    ) internal returns (MigrationContext memory ctx) {
        MigrationContext memory ctx;
        ctx.spell = spell;
        ctx.vaultOld = IVaultOld(spell.VAULT_OLD());
        ctx.trancheTokenToMigrate = Tranche(ctx.vaultOld.share());
        ctx.poolId = ctx.vaultOld.poolId();
        ctx.trancheId = ctx.vaultOld.trancheId();

        setupAuthAndBalances(ctx, root, poolManager, restrictionManager, adminMultisig, guardian);

        spell.testCastPartOne(address(root), address(poolManager), address(restrictionManager));

        // assert vault and tranche were deployed
        assertTrue(PoolManager(poolManager).getVault(ctx.poolId, ctx.trancheId, ctx.vaultOld.asset()) != address(0));
        assertTrue(PoolManager(poolManager).getTranche(ctx.poolId, ctx.trancheId) != address(0));
        return ctx;
    }

    function migrateSharesPartTwo(
        MigrationContext memory ctx,
        address root,
        address poolManager,
        address restrictionManager
    ) internal {
        TestableSpell spell = ctx.spell;
        spell.testCastPartTwo(address(root), address(poolManager), address(restrictionManager));

        ctx.trancheToken = Tranche(address(PoolManager(poolManager).getTranche(ctx.poolId, ctx.trancheId)));

        verifyMigration(ctx, root, poolManager);
    }

    function setupAuthAndBalances(
        MigrationContext memory ctx,
        address root,
        address poolManager,
        address restrictionManager,
        address adminMultisig,
        address guardian
    ) internal {
        ctx.totalSupplyOld = 0;
        for (uint8 i; i < ctx.spell.getNumberOfMigratedMembers(); i++) {
            ctx.totalSupplyOld += ctx.trancheTokenToMigrate.balanceOf(ctx.spell.memberlistMembers(i));
        }
        assertEq(ctx.trancheTokenToMigrate.totalSupply(), ctx.totalSupplyOld);

        Guardian guardianOld = Guardian(ctx.spell.GUARDIAN_OLD());
        vm.prank(ctx.spell.ADMIN_MULTISIG());
        guardianOld.scheduleRely(address(ctx.spell));

        Guardian guardian = Guardian(guardian);
        vm.prank(adminMultisig);
        guardian.scheduleRely(address(ctx.spell));

        vm.warp(block.timestamp + 2 days);
        Root rootOld = Root(ctx.spell.ROOT_OLD());
        rootOld.executeScheduledRely(address(ctx.spell));
        Root(root).executeScheduledRely(address(ctx.spell));

        for (uint8 i; i < ctx.spell.getNumberOfMigratedMembers(); i++) {
            if (ctx.spell.memberlistMembers(i) != ctx.vaultOld.escrow()) {
                uint256 maxMint = IInvestmentManager(ctx.vaultOld.manager()).maxMint(
                    ctx.spell.VAULT_OLD(), ctx.spell.memberlistMembers(i)
                );
                balancesOld[ctx.spell.memberlistMembers(i)][address(ctx.trancheTokenToMigrate)] =
                    ctx.trancheTokenToMigrate.balanceOf(ctx.spell.memberlistMembers(i)) + maxMint;
            }
        }
    }

    function verifyMigration(MigrationContext memory ctx, address root, address poolManager) internal {
        ctx.totalSupplyNew = 0;
        for (uint8 i; i < ctx.spell.getNumberOfMigratedMembers(); i++) {
            uint256 balanceNew = ctx.trancheToken.balanceOf(ctx.spell.memberlistMembers(i));
            ctx.totalSupplyNew += balanceNew;
            assertApproxEqAbs(ctx.trancheTokenToMigrate.balanceOf(ctx.spell.memberlistMembers(i)), 0, 1);
            if (ctx.spell.memberlistMembers(i) != ctx.vaultOld.escrow()) {
                assertApproxEqAbs(balanceNew, balancesOld[ctx.spell.memberlistMembers(i)][address(ctx.trancheTokenToMigrate)], 1);
            }
        }
        assertApproxEqAbs(ctx.trancheTokenToMigrate.balanceOf(ctx.vaultOld.escrow()), 0, 1);

        assertApproxEqAbs(ctx.trancheToken.totalSupply(), ctx.totalSupplyNew, 1);
        assertApproxEqAbs(ctx.trancheToken.totalSupply(), ctx.totalSupplyOld, 1);
        assertApproxEqAbs(ctx.trancheTokenToMigrate.totalSupply(), 0, 1);

        assertEq(ctx.trancheTokenToMigrate.name(), ctx.spell.NAME_OLD());
        assertEq(ctx.trancheTokenToMigrate.symbol(), ctx.spell.SYMBOL_OLD());
        assertEq(ctx.trancheToken.name(), ctx.spell.NAME());
        assertEq(ctx.trancheToken.symbol(), ctx.spell.SYMBOL());
        assertEq(ctx.trancheToken.decimals(), ctx.trancheTokenToMigrate.decimals());

        assertEq(Auth(address(poolManager)).wards(address(ctx.spell)), 0);
        assertEq(Auth(address(ctx.trancheToken)).wards(address(ctx.spell)), 0);
        assertEq(Auth(address(ctx.trancheTokenToMigrate)).wards(address(ctx.spell)), 0);
        assertEq(Auth(ctx.vaultOld.manager()).wards(address(ctx.spell)), 0);
        assertEq(Auth(ctx.spell.ROOT_OLD()).wards(address(ctx.spell)), 0);
        assertEq(Auth(address(root)).wards(address(ctx.spell)), 0);
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
}
