pragma solidity 0.8.26;

import {IRoot} from "src/interfaces/IRoot.sol";
import {IPoolManager} from "src/interfaces/IPoolManager.sol";
import {RestrictionUpdate} from "src/interfaces/token/IRestrictionManager.sol";
import {ITranche} from "src/interfaces/token/ITranche.sol";
import {IInvestmentManager} from "src/interfaces/IInvestmentManager.sol";
import {IAuth} from "src/interfaces/IAuth.sol";
import {MigrationSpellBase} from "src/spell/MigrationSpellBase.sol";

interface ITrancheOld {
    function authTransferFrom(address from, address to, uint256 value) external returns (bool);
}

// spell to migrate tranche tokens
contract MigrationSpell is MigrationSpellBase {
    constructor() {
        NETWORK = "ethereum-mainnet";
        // old deployment addresses
        CURRENCY_ID = 242333941209166991950178742833476896417;
        ROOT_OLD = 0x498016d30Cd5f0db50d7ACE329C07313a0420502;
        ADMIN_MULTISIG = 0xD9D30ab47c0f096b0AA67e9B8B1624504a63e7FD;
        GUARDIAN_OLD = 0x2559998026796Ca6fd057f3aa66F2d6ecdEd9028;

        // old pool addresses
        VAULT_OLD = 0x110379504D933BeD2E485E281bc3909D1E7C9E5D;

        // new deployment addresses
        ROOT_NEW = 0x0000000000000000000000000000000000000000; // TODO - set
        GUARDIAN_NEW = 0x0000000000000000000000000000000000000000; // TODO - set
        POOLMANAGER_NEW = 0x0000000000000000000000000000000000000000; // TODO - set
        RESTRICTIONMANAGER_NEW = 0x0000000000000000000000000000000000000000; // TODO - set

        // information to deploy the new tranche token & liquidity pool to be able to migrate the tokens
        NAME = "Anemoy DeFi Yield Fund 1 SP DeFi Yield Fund Token";
        SYMBOL = "DYF";
        NAME_OLD = "DEPRECATED";
        SYMBOL_OLD = "DEPRECATED";

        memberlistMembers = [0xd595E1483c507E74E2E6A3dE8e7D08d8f6F74936, 0x30d3bbAE8623d0e9C0db5c27B82dCDA39De40997];
        validUntil[0xd595E1483c507E74E2E6A3dE8e7D08d8f6F74936] = type(uint64).max;
        validUntil[0x30d3bbAE8623d0e9C0db5c27B82dCDA39De40997] = 2032178598;
    }
}
