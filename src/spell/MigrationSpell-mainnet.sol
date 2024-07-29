pragma solidity 0.8.26;

import {IRoot} from "src/interfaces/IRoot.sol";
import {IPoolManager} from "src/interfaces/IPoolManager.sol";
import {RestrictionUpdate} from "src/interfaces/token/IRestrictionManager.sol";
import {ITranche} from "src/interfaces/token/ITranche.sol";
import {CastLib} from "src/libraries/CastLib.sol";

interface ITrancheOld {
    function authTransferFrom(address from, address to, uint256 value) external returns (bool);
}

// spell to migrate tranche tokens
contract MigrationSpell {
    using CastLib for *;

    // addresses of the old liquidity pool deployment
    address public constant TRANCHE_TOKEN_OLD = 0x30baA3BA9D7089fD8D020a994Db75D14CF7eC83b;
    address public constant ROOT_OLD = 0x498016d30Cd5f0db50d7ACE329C07313a0420502;

    // addresses of the new liquidity pool deployment
    address public constant ROOT_NEW = 0x0000000000000000000000000000000000000000; // TODO - set
    address public constant POOLMANAGER = 0x0000000000000000000000000000000000000000; // TODO - set
    address public constant RESTRICTIONMANEGER = 0x0000000000000000000000000000000000000000; // TODO - set
    ITranche public trancheTokenNew; // to be deployed during spell exec

    // information to deploy the new tranche token & liquidity pool to be able to migrate the tokens
    uint64 public constant POOL_ID = 4139607887;
    bytes16 public constant TRANCHE_ID = 0x97aa65f23e7be09fcd62d0554d2e9273;
    uint8 public constant DECIMALS = 6;
    string public constant NAME = "Anemoy Liquid Treasury Fund 1";
    string public constant SYMBOL = "LTF";

    string public constant NAME_OLD = "DEPRECATED";
    string public constant SYMBOL_OLD = "DEPRECATED";

    // addresses of the holders of the old tranche token
    address[] public trancheTokenHolders = [
        0x30d3bbAE8623d0e9C0db5c27B82dCDA39De40997,
        0x2923c1B5313F7375fdaeE80b7745106deBC1b53E,
        0xd595E1483c507E74E2E6A3dE8e7D08d8f6F74936
    ];

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
        IPoolManager poolManager = IPoolManager(address(POOLMANAGER));
        ITranche trancheTokenOld = ITranche(TRANCHE_TOKEN_OLD);

        // deploy new tranche token
        rootNew.relyContract(address(POOLMANAGER), self);
        poolManager.addPool(POOL_ID);
        poolManager.addTranche(POOL_ID, TRANCHE_ID, NAME, SYMBOL, DECIMALS, RESTRICTIONMANEGER);
        trancheTokenNew = ITranche(poolManager.deployTranche(POOL_ID, TRANCHE_ID));
        rootNew.relyContract(address(trancheTokenNew), self);

        // transfer old tokens from holders` wallets
        // add holders to the allowlist of new tranche token
        // mint new tokens to holders' wallets
        uint256 holderBalance;
        for (uint8 i; i < trancheTokenHolders.length; i++) {
            holderBalance = trancheTokenOld.balanceOf(trancheTokenHolders[i]);

            // mint new token to the holders wallet
            poolManager.updateRestriction(
                POOL_ID,
                TRANCHE_ID,
                abi.encodePacked(
                    uint8(RestrictionUpdate.UpdateMember), address(trancheTokenHolders[i]).toBytes32(), type(uint64).max
                )
            ); // add to allowlist
            trancheTokenNew.mint(trancheTokenHolders[i], holderBalance);
            ITrancheOld(TRANCHE_TOKEN_OLD).authTransferFrom(trancheTokenHolders[i], self, holderBalance);
        }
        // burn entire supply of old tranche tokens
        trancheTokenOld.burn(self, trancheTokenOld.balanceOf(self));

        // rename old tranche token
        trancheTokenOld.file("name", NAME_OLD);
        trancheTokenOld.file("symbol", SYMBOL_OLD);

        // denies
    }

    function getNumberOfMigratedHolders() public view returns (uint256) {
        return trancheTokenHolders.length;
    }
}
