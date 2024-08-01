// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.26;

import {IRoot} from "src/interfaces/IRoot.sol";
import {IPoolManager} from "src/interfaces/IPoolManager.sol";
import {RestrictionUpdate} from "src/interfaces/token/IRestrictionManager.sol";
import {ITranche} from "src/interfaces/token/ITranche.sol";
import {InvestmentManager} from "src/InvestmentManager.sol";
import {CastLib} from "src/libraries/CastLib.sol";
import {IAuth} from "src/interfaces/IAuth.sol";

interface ITrancheOld {
    function authTransferFrom(address from, address to, uint256 value) external returns (bool);
}

interface IVaultOld {
    function poolId() external view returns (uint64);
    function trancheId() external view returns (bytes16);
    function share() external view returns (address);
    function manager() external view returns (address);
    function escrow() external view returns (address);
    function asset() external view returns (address);
}

interface IPoolManagerOld {
    function currencyAddressToId(address currency) external view returns (uint128);
}

contract MigrationSpellBase {
    using CastLib for *;

    string public NETWORK;
    address public ROOT_NEW;
    IRoot public rootNew;
    address public GUARDIAN_NEW;
    address public POOLMANAGER_NEW;
    address public RESTRICTIONMANAGER_NEW;
    ITranche public trancheTokenNew;
    IPoolManager poolManager;

    address public ROOT_OLD;
    IRoot public rootOld;
    address public ADMIN_MULTISIG;
    address public GUARDIAN_OLD;
    address public VAULT_OLD;
    uint64 POOL_ID;
    bytes16 TRANCHE_ID;
    uint8 DECIMALS;
    uint128 CURRENCY_ID;
    IVaultOld public vaultOld;
    ITranche trancheTokenOld;
    InvestmentManager investmentManagerOld;
    IPoolManagerOld poolManagerOld;

    string public NAME;
    string public SYMBOL;
    string public NAME_OLD;
    string public SYMBOL_OLD;
    address[] public memberlistMembers;
    mapping(address => uint64) public validUntil;
    bool public partOneDone;
    bool public partTwoDone;
    uint256 constant ONE = 10 ** 27;
    address self;

    function castPartOne() public {
        require(!partOneDone, "spell-already-cast");
        partOneDone = true;
        executePartOne();
    }

    function castPartTwo() public {
        require(partOneDone, "part-one-not-cast");
        require(!partTwoDone, "spell-already-cast");
        partTwoDone = true;
        executePartTwo();
    }

    function executePartOne() internal {
        self = address(this);
        rootOld = IRoot(address(ROOT_OLD));
        rootNew = IRoot(address(ROOT_NEW));
        vaultOld = IVaultOld(VAULT_OLD);
        POOL_ID = vaultOld.poolId();
        TRANCHE_ID = vaultOld.trancheId();
        poolManager = IPoolManager(address(POOLMANAGER_NEW));
        trancheTokenOld = ITranche(vaultOld.share());
        DECIMALS = trancheTokenOld.decimals();
        investmentManagerOld = InvestmentManager(vaultOld.manager());
        poolManagerOld = IPoolManagerOld(address(investmentManagerOld.poolManager()));
        CURRENCY_ID = poolManagerOld.currencyAddressToId(vaultOld.asset());
        rootOld.relyContract(address(investmentManagerOld), self);
        rootOld.relyContract(address(trancheTokenOld), self);

        // deploy new tranche token
        rootNew.relyContract(address(POOLMANAGER_NEW), self);
        poolManager.addPool(POOL_ID);
        poolManager.addTranche(POOL_ID, TRANCHE_ID, NAME, SYMBOL, DECIMALS, RESTRICTIONMANAGER_NEW);
        poolManager.addAsset(CURRENCY_ID, vaultOld.asset());
        poolManager.allowAsset(POOL_ID, CURRENCY_ID);
        trancheTokenNew = ITranche(poolManager.deployTranche(POOL_ID, TRANCHE_ID));
        rootNew.relyContract(address(trancheTokenNew), self);
        poolManager.deployVault(POOL_ID, TRANCHE_ID, vaultOld.asset());
    }

    function executePartTwo() internal {
        // add all old members to new memberlist and claim any tokens
        uint256 holderBalance;
        for (uint8 i; i < memberlistMembers.length; i++) {
            // add member to new memberlist
            poolManager.updateRestriction(
                POOL_ID,
                TRANCHE_ID,
                abi.encodePacked(
                    uint8(RestrictionUpdate.UpdateMember),
                    address(memberlistMembers[i]).toBytes32(),
                    validUntil[memberlistMembers[i]]
                )
            );
            if (memberlistMembers[i] != vaultOld.escrow()) {
                uint256 maxMint = investmentManagerOld.maxMint(VAULT_OLD, memberlistMembers[i]);
                if (maxMint > 0) {
                    // Claim any unclaimed tokens the user may have
                    investmentManagerOld.mint(VAULT_OLD, maxMint, memberlistMembers[i], memberlistMembers[i]);
                }
                holderBalance = trancheTokenOld.balanceOf(memberlistMembers[i]);
                if (holderBalance > 0) {
                    // mint new token to the holder's wallet
                    trancheTokenNew.mint(memberlistMembers[i], holderBalance);
                    // transfer old tokens from holders' wallets
                    ITrancheOld(vaultOld.share()).authTransferFrom(memberlistMembers[i], self, holderBalance);
                }
            }
        }

        // burn entire supply of old tranche tokens
        trancheTokenOld.burn(self, trancheTokenOld.balanceOf(self));

        // rename old tranche token
        trancheTokenOld.file("name", NAME_OLD);
        trancheTokenOld.file("symbol", SYMBOL_OLD);

        // denies
        rootNew.denyContract(address(POOLMANAGER_NEW), self);
        rootNew.denyContract(address(trancheTokenNew), self);
        rootOld.denyContract(address(trancheTokenOld), self);
        rootOld.denyContract(address(investmentManagerOld), self);
        IAuth(address(rootOld)).deny(self);
        IAuth(address(rootNew)).deny(self);
    }

    function getNumberOfMigratedMembers() public view returns (uint256) {
        return memberlistMembers.length;
    }
}
