// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.26;

import {Guardian} from "src/admin/Guardian.sol";
import {Auth} from "src/Auth.sol";
import "./MigrationSpell-mainnet.sol";
import "forge-std/Test.sol";
import "forge-std/StdJson.sol";

contract MigrationSpellTest is Test {
    using stdJson for string;

    string[] deployments;
    MigrationSpell spell;

    // set this variables custom for each network
    Guardian guardianOld = Guardian(address(0x2559998026796Ca6fd057f3aa66F2d6ecdEd9028));
    Guardian guardianNew = Guardian(address(0x0000000000000000000000000000000000000000)); // TODO set address
    address adminMultiSig = 0xD9D30ab47c0f096b0AA67e9B8B1624504a63e7FD;

    address self;

    ITranche trancheTokenOld;

    function setUp() public {
        self = address(this);
        _loadDeployment("mainnet", "ethereum-mainnet"); // Mainnet
        _loadFork(0);
        spell = new MigrationSpell();

        trancheTokenOld = ITranche(spell.TRANCHE_TOKEN_OLD());
    }

    function testMigration() public {
        // check if spell is migrating all the current token holders
        uint256 holdersSupplySum;
        uint256[] memory trancheTokenHolderBalancesOld = new uint256[](spell.getNumberOfMigratedMembers());
        uint256 balanceOld;

        for (uint8 i; i < spell.getNumberOfMigratedMembers(); i++) {
            balanceOld = trancheTokenOld.balanceOf(spell.memberlistMembers(i));
            trancheTokenHolderBalancesOld[i] = balanceOld;
            holdersSupplySum += balanceOld;
        }
        assertEq(trancheTokenOld.totalSupply(), holdersSupplySum);

        // simulate manual governance steps
        vm.startPrank(adminMultiSig);
        guardianOld.scheduleRely(self);
        guardianNew.scheduleRely(self);
        vm.stopPrank();
        // warp delay time = 48H & exec relies
        vm.warp(block.timestamp + 2 days);
        IRoot(spell.ROOT_OLD()).executeScheduledRely(self);
        IRoot(spell.ROOT_NEW()).executeScheduledRely(self);

        // cast spell
        spell.cast();

        // for all members check if balance was migrated correctly
        uint256 balanceNew;
        for (uint8 i; i < spell.getNumberOfMigratedMembers(); i++) {
            balanceNew = spell.trancheTokenNew().balanceOf(spell.memberlistMembers(i));
            // assert users new token balance equals old token balance
            assertEq(trancheTokenHolderBalancesOld[i], balanceNew);
            // assert old tokens got removed from user wallet
            assertEq(trancheTokenOld.balanceOf(spell.memberlistMembers(i)), 0);
        }
        // assert all old tokens were claimed from escrow
        assertEq(trancheTokenOld.balanceOf(spell.ESCROW_OLD()), 0);
        // assert total new supply equeals total old supply
        assertEq(spell.trancheTokenNew().totalSupply(), holdersSupplySum);
        // assert all old tokens burned
        assertEq(trancheTokenOld.totalSupply(), 0);

        // assert renaming of old trancheToken worked
        assertEq(trancheTokenOld.name(), spell.NAME_OLD());
        assertEq(trancheTokenOld.symbol(), spell.SYMBOL_OLD());

        // assert new trancheToken metadata
        assertEq(spell.trancheTokenNew().name(), spell.NAME());
        assertEq(spell.trancheTokenNew().symbol(), spell.SYMBOL());
        assertEq(spell.trancheTokenNew().decimals(), spell.DECIMALS());

        // assert denies
        assertEq(Auth(spell.POOLMANAGER()).wards(address(spell)), 0);
        assertEq(Auth(address(spell.trancheTokenNew())).wards(address(spell)), 0);
        assertEq(Auth(spell.INVESTMENTMANAGER_OLD()).wards(address(spell)), 0);
        assertEq(Auth(spell.ROOT_OLD()).wards(address(spell)), 0);
        assertEq(Auth(spell.ROOT_NEW()).wards(address(spell)), 0);
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
