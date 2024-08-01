// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.26;

import {IRoot} from "src/interfaces/IRoot.sol";
import {IPoolManager} from "src/interfaces/IPoolManager.sol";
import {RestrictionUpdate} from "src/interfaces/token/IRestrictionManager.sol";
import {ITranche} from "src/interfaces/token/ITranche.sol";
import {IInvestmentManager} from "src/interfaces/IInvestmentManager.sol";
import {CastLib} from "src/libraries/CastLib.sol";
import {IAuth} from "src/interfaces/IAuth.sol";

interface ITrancheOld {
    function authTransferFrom(address from, address to, uint256 value) external returns (bool);
}

contract MigrationSpellBase {
    using CastLib for *;

    string public NETWORK;
    address public CURRENCY;
    uint128 public CURRENCY_ID;
    address public ESCROW_OLD;
    address public INVESTMENTMANAGER_OLD;
    address public ROOT_OLD;
    address public ADMIN_MULTISIG;
    address public GUARDIAN_OLD;
    address public TRANCHE_TOKEN_OLD;
    address public VAULT_OLD;
    address public ROOT_NEW;
    address public GUARDIAN_NEW;
    address public POOLMANAGER_NEW;
    address public RESTRICTIONMANAGER_NEW;
    ITranche public trancheTokenNew;
    uint64 public POOL_ID;
    bytes16 public TRANCHE_ID;
    uint8 public DECIMALS;
    string public NAME;
    string public SYMBOL;
    string public NAME_OLD;
    string public SYMBOL_OLD;
    address[] public memberlistMembers;
    mapping(address => uint64) public validUntil;
    bool public done;
    uint256 constant ONE = 10 ** 27;
    address self;

    function cast() public {
        require(!done, "spell-already-cast");
        done = true;
        execute();
    }

    function execute() internal {
        self = address(this);
        IRoot rootOld = IRoot(address(ROOT_OLD));
        IRoot rootNew = IRoot(address(ROOT_NEW));
        IPoolManager poolManager = IPoolManager(address(POOLMANAGER_NEW));
        ITranche trancheTokenOld = ITranche(TRANCHE_TOKEN_OLD);
        IInvestmentManager investmentManagerOld = IInvestmentManager(address(INVESTMENTMANAGER_OLD));
        rootOld.relyContract(address(investmentManagerOld), self);
        rootOld.relyContract(address(trancheTokenOld), self);

        // deploy new tranche token
        rootNew.relyContract(address(POOLMANAGER_NEW), self);
        poolManager.addPool(POOL_ID);
        poolManager.addTranche(POOL_ID, TRANCHE_ID, NAME, SYMBOL, DECIMALS, RESTRICTIONMANAGER_NEW);
        poolManager.addAsset(CURRENCY_ID, CURRENCY);
        poolManager.allowAsset(POOL_ID, CURRENCY_ID);
        trancheTokenNew = ITranche(poolManager.deployTranche(POOL_ID, TRANCHE_ID));
        rootNew.relyContract(address(trancheTokenNew), self);

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
            if (memberlistMembers[i] != ESCROW_OLD) {
                uint256 maxMint = investmentManagerOld.maxMint(VAULT_OLD, memberlistMembers[i]);
                if (maxMint > 0) {
                    // Claim any unclaimed tokens the user may have
                    investmentManagerOld.mint(
                        VAULT_OLD,
                        investmentManagerOld.maxMint(VAULT_OLD, memberlistMembers[i]),
                        memberlistMembers[i],
                        memberlistMembers[i]
                    );
                }
                holderBalance = trancheTokenOld.balanceOf(memberlistMembers[i]);
                if (holderBalance > 0) {
                    // mint new token to the holder's wallet
                    trancheTokenNew.mint(memberlistMembers[i], holderBalance);
                    // transfer old tokens from holders' wallets
                    ITrancheOld(TRANCHE_TOKEN_OLD).authTransferFrom(memberlistMembers[i], self, holderBalance);
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

        poolManager.deployVault(POOL_ID, TRANCHE_ID, CURRENCY);
    }

    function getNumberOfMigratedMembers() public view returns (uint256) {
        return memberlistMembers.length;
    }
}
