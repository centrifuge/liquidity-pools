pragma solidity 0.8.26;

import {MigrationSpellBase} from "src/spell/MigrationSpellBase.sol";

interface ITrancheOld {
    function authTransferFrom(address from, address to, uint256 value) external returns (bool);
}

contract MigrationSpell is MigrationSpellBase {
    constructor() {
        NETWORK = "base-mainnet";
        // old deployment addresses
        ROOT_OLD = 0x498016d30Cd5f0db50d7ACE329C07313a0420502;
        ADMIN_MULTISIG = 0x8b83962fB9dB346a20c95D98d4E312f17f4C0d9b;
        GUARDIAN_OLD = 0x2559998026796Ca6fd057f3aa66F2d6ecdEd9028;

        // old pool addresses
        VAULT_OLD = 0xa0872E8D2975483b2Ab4Afcee729133D8666F6f5;

        // new deployment addresses
        ROOT_NEW = 0x0C1fDfd6a1331a875EA013F3897fc8a76ada5DfC;
        GUARDIAN_NEW = 0x427A1ce127b1775e4Cbd4F58ad468B9F832eA7e9;
        POOLMANAGER_NEW = 0x7f192F34499DdB2bE06c4754CFf2a21c4B056994;
        RESTRICTIONMANAGER_NEW = 0x4737C3f62Cc265e786b280153fC666cEA2fBc0c0;

        // information to deploy the new tranche token & liquidity pool to be able to migrate the tokens
        NAME = "Anemoy Liquid Treasury Fund 1";
        SYMBOL = "LTF";

        NAME_OLD = "LTF (deprecated)";
        SYMBOL_OLD = "LTF-DEPRECATED";

        memberlistMembers = [
            0xd595E1483c507E74E2E6A3dE8e7D08d8f6F74936,
            0xBBBBBbbBBb9cC5e90e3b3Af64bdAF62C37EEFFCb,
            0x86552B8d4F4a600D92d516eE8eA8B922EFEcB561
        ];

        validUntil[0xd595E1483c507E74E2E6A3dE8e7D08d8f6F74936] = type(uint64).max;
        validUntil[0xBBBBBbbBBb9cC5e90e3b3Af64bdAF62C37EEFFCb] = 2035284942;
        validUntil[0x86552B8d4F4a600D92d516eE8eA8B922EFEcB561] = 2037188297;
    }
}
