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

    // addresses of the old liquidity pool deployment
    address public constant TRANCHE_TOKEN_OLD = 0x30baA3BA9D7089fD8D020a994Db75D14CF7eC83b;
    address public constant ROOT_OLD = 0x498016d30Cd5f0db50d7ACE329C07313a0420502;
    address public constant ESCROW_OLD = 0xd595E1483c507E74E2E6A3dE8e7D08d8f6F74936;
    address public constant INVESTMENTMANAGER_OLD = 0xbBF0AB988691dB1892ADaF7F0eF560Ca4c6DD73A;
    address public constant VAULT_OLD = 0xB3AC09cd5201569a821d87446A4aF1b202B10aFd; // liquidityPool

    // addresses of the new liquidity pool deployment
    address public constant ROOT_NEW = 0x0000000000000000000000000000000000000000; // TODO - set
    address public constant POOLMANAGER = 0x0000000000000000000000000000000000000000; // TODO - set
    address public constant RESTRICTIONMANAGER = 0x0000000000000000000000000000000000000000; // TODO - set
    ITranche public trancheTokenNew; // to be deployed during spell exec

    // information to deploy the new tranche token & liquidity pool to be able to migrate the tokens
    uint64 public constant POOL_ID = 4139607887;
    bytes16 public constant TRANCHE_ID = 0x97aa65f23e7be09fcd62d0554d2e9273;
    uint8 public constant DECIMALS = 6;
    string public constant NAME = "Anemoy Liquid Treasury Fund 1";
    string public constant SYMBOL = "LTF";

    string public constant NAME_OLD = "DEPRECATED";
    string public constant SYMBOL_OLD = "DEPRECATED";

    // // addresses of the holders of the old tranche token
    // address[] public trancheTokenHolders = [
    //     0x30d3bbAE8623d0e9C0db5c27B82dCDA39De40997,
    //     0x2923c1B5313F7375fdaeE80b7745106deBC1b53E,
    //     0xd595E1483c507E74E2E6A3dE8e7D08d8f6F74936
    // ];

    address[] public memberlistMembers = [
        0xd595E1483c507E74E2E6A3dE8e7D08d8f6F74936,
        0xeF08Bb6F5F9494faf2316402802e54089E6322eb,
        0x30d3bbAE8623d0e9C0db5c27B82dCDA39De40997,
        0xeEDC395aAAb05e5fb6130A8C5AEbAE48E7739B78,
        0x2923c1B5313F7375fdaeE80b7745106deBC1b53E,
        0x14FFe68D005e58f08c27dC0c999f75639682276c,
        0x86552B8d4F4a600D92d516eE8eA8B922EFEcB561
    ];

    mapping(address => uint256) public validUntil;
    bool public done;
    uint256 constant ONE = 10 ** 27;
    address self;

    constructor() {
        validUntil[0xd595E1483c507E74E2E6A3dE8e7D08d8f6F74936] = type(uint64).max;
        validUntil[0xeF08Bb6F5F9494faf2316402802e54089E6322eb] = 2017150288;
        validUntil[0x30d3bbAE8623d0e9C0db5c27B82dCDA39De40997] = 2017323212;
        validUntil[0xeEDC395aAAb05e5fb6130A8C5AEbAE48E7739B78] = 3745713365;
        validUntil[0x2923c1B5313F7375fdaeE80b7745106deBC1b53E] = 2031229099;
        validUntil[0x14FFe68D005e58f08c27dC0c999f75639682276c] = 2035299660;
        validUntil[0x86552B8d4F4a600D92d516eE8eA8B922EFEcB561] = 2037188261;
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

        // deploy new tranche token
        rootNew.relyContract(address(POOLMANAGER), self);
        poolManager.addPool(POOL_ID);
        poolManager.addTranche(POOL_ID, TRANCHE_ID, NAME, SYMBOL, DECIMALS, RESTRICTIONMANAGER);
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
                    uint8(RestrictionUpdate.UpdateMember), address(memberlistMembers[i]).toBytes32(), validUntil[memberlistMembers[i]]
                )
            );

            if (escrowBalance > 0) {
                // Claim any unclaimed tokens the user may have
                investmentManagerOld.mint(VAULT_OLD, investmentManagerOld.maxMint(VAULT_OLD, memberlistMembers[i]), memberlistMembers[i], memberlistMembers[i]);
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
        rootOld.denyContract(address(investmentManagerOld), self);
        IAuth(address(rootOld)).deny(self);
        IAuth(address(rootNew)).deny(self);
    }

    function getNumberOfMigratedMembers() public view returns (uint256) {
        return memberlistMembers.length;
    }
}
