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

// spell to migrate tranche tokens
contract MigrationSpell {
    using CastLib for *;

    // old deployment addresses
    address public constant CURRENCY = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48; // USDC
    uint128 public constant CURRENCY_ID = 242333941209166991950178742833476896417;
    address public constant ESCROW_OLD = 0xd595E1483c507E74E2E6A3dE8e7D08d8f6F74936;
    address public constant INVESTMENTMANAGER_OLD = 0xbBF0AB988691dB1892ADaF7F0eF560Ca4c6DD73A;
    address public constant ROOT_OLD = 0x498016d30Cd5f0db50d7ACE329C07313a0420502;
    address public constant ADMIN_MULTISIG = 0xD9D30ab47c0f096b0AA67e9B8B1624504a63e7FD;
    address public constant GUARDIAN_OLD = 0x2559998026796Ca6fd057f3aa66F2d6ecdEd9028;

    // old pool addresses
    address public constant TRANCHE_TOKEN_OLD = 0x143dB3a0d0679DFd3372e7F3877BbBB27da3f5e4;
    address public constant VAULT_OLD = 0x110379504D933BeD2E485E281bc3909D1E7C9E5D;

    // new deployment addresses
    address public ROOT_NEW = 0x0000000000000000000000000000000000000000; // TODO - set
    address public POOLMANAGER = 0x0000000000000000000000000000000000000000; // TODO - set
    address public RESTRICTIONMANAGER = 0x0000000000000000000000000000000000000000; // TODO - set
    ITranche public trancheTokenNew; // to be deployed during spell exec

    // information to deploy the new tranche token & liquidity pool to be able to migrate the tokens
    uint64 public constant POOL_ID = 1655476167;
    bytes16 public constant TRANCHE_ID = 0x4859c6f181b1b993c35b313bedb949cf;
    uint8 public constant DECIMALS = 6;
    string public constant NAME = "Anemoy DeFi Yield Fund 1 SP DeFi Yield Fund Token";
    string public constant SYMBOL = "DYF";

    string public constant NAME_OLD = "DEPRECATED";
    string public constant SYMBOL_OLD = "DEPRECATED";

    address[] public memberlistMembers =
        [0xd595E1483c507E74E2E6A3dE8e7D08d8f6F74936, 0x30d3bbAE8623d0e9C0db5c27B82dCDA39De40997];

    mapping(address => uint64) public validUntil;
    bool public done;
    uint256 constant ONE = 10 ** 27;
    address self;

    constructor() {
        validUntil[0xd595E1483c507E74E2E6A3dE8e7D08d8f6F74936] = type(uint64).max;
        validUntil[0x30d3bbAE8623d0e9C0db5c27B82dCDA39De40997] = 2032178598;
    }

    function cast() public {
        require(!done, "spell-already-cast");
        done = true;
        execute();
    }

    function execute() internal {
        self = address(this);
        IRoot rootOld = IRoot(address(ROOT_OLD));
        IRoot rootNew = IRoot(address(ROOT_NEW));
        IPoolManager poolManager = IPoolManager(address(POOLMANAGER));
        ITranche trancheTokenOld = ITranche(TRANCHE_TOKEN_OLD);
        IInvestmentManager investmentManagerOld = IInvestmentManager(address(INVESTMENTMANAGER_OLD));
        rootOld.relyContract(address(investmentManagerOld), self);
        rootOld.relyContract(address(trancheTokenOld), self);

        // deploy new tranche token
        rootNew.relyContract(address(POOLMANAGER), self);
        poolManager.addPool(POOL_ID);
        poolManager.addTranche(POOL_ID, TRANCHE_ID, NAME, SYMBOL, DECIMALS, RESTRICTIONMANAGER);
        poolManager.addAsset(CURRENCY_ID, CURRENCY);
        poolManager.allowAsset(POOL_ID, CURRENCY_ID);
        trancheTokenNew = ITranche(poolManager.deployTranche(POOL_ID, TRANCHE_ID));
        rootNew.relyContract(address(trancheTokenNew), self);

        // add all old members to new memberlist and claim any tokens
        uint256 holderBalance;
        uint256 escrowBalance = trancheTokenOld.balanceOf(ESCROW_OLD);
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

            if (escrowBalance > 0) {
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

        // burn entire supply of old tranche tokens
        trancheTokenOld.burn(self, trancheTokenOld.balanceOf(self));

        // rename old tranche token
        trancheTokenOld.file("name", NAME_OLD);
        trancheTokenOld.file("symbol", SYMBOL_OLD);

        // denies
        rootNew.denyContract(address(POOLMANAGER), self);
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
