pragma solidity 0.8.26;

import {MigrationSpellBase} from "src/spell/MigrationSpellBase.sol";

interface ITrancheOld {
    function authTransferFrom(address from, address to, uint256 value) external returns (bool);
}

contract MigrationSpell is MigrationSpellBase {
    constructor() {
        NETWORK = "ethereum-mainnet";
        // old deployment addresses
        CURRENCY_ID = 242333941209166991950178742833476896417;
        ROOT_OLD = 0x498016d30Cd5f0db50d7ACE329C07313a0420502;
        ADMIN_MULTISIG = 0xD9D30ab47c0f096b0AA67e9B8B1624504a63e7FD;
        GUARDIAN_OLD = 0x2559998026796Ca6fd057f3aa66F2d6ecdEd9028;

        // old pool addresses
        VAULT_OLD = 0xd0C7E8C9b0c82b74771AE13e184432240A3a2F54;

        // new deployment addresses
        ROOT_NEW = 0x0C1fDfd6a1331a875EA013F3897fc8a76ada5DfC;
        GUARDIAN_NEW = 0x09ab10a9c3E6Eac1d18270a2322B6113F4C7f5E8;
        POOLMANAGER_NEW = 0x91808B5E2F6d7483D41A681034D7c9DbB64B9E29;
        RESTRICTIONMANAGER_NEW = 0x4737C3f62Cc265e786b280153fC666cEA2fBc0c0;

        // information to deploy the new tranche token & liquidity pool to be able to migrate the tokens
        NAME = "New Silver Series 3 Junior";
        SYMBOL = "NS3JR";

        NAME_OLD = "DEPRECATED";
        SYMBOL_OLD = "DEPRECATED";

        memberlistMembers = [0xd595E1483c507E74E2E6A3dE8e7D08d8f6F74936, 0x32f5eF78AA9C7b8882D748331AdcFe0dfA4f1a14];

        validUntil[0xd595E1483c507E74E2E6A3dE8e7D08d8f6F74936] = type(uint64).max;
        validUntil[0x32f5eF78AA9C7b8882D748331AdcFe0dfA4f1a14] = 2030638540;
    }
}
