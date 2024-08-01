pragma solidity 0.8.26;

import {MigrationSpellBase} from "src/spell/MigrationSpellBase.sol";

// spell to migrate tranche tokens
contract MigrationSpell is MigrationSpellBase {

    constructor() {
        NETWORK = "ethereum-mainnet";
        // old deployment addresses
        CURRENCY = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48; // USDC
        CURRENCY_ID = 242333941209166991950178742833476896417;
        ESCROW_OLD = 0xd595E1483c507E74E2E6A3dE8e7D08d8f6F74936;
        INVESTMENTMANAGER_OLD = 0xbBF0AB988691dB1892ADaF7F0eF560Ca4c6DD73A;
        ROOT_OLD = 0x498016d30Cd5f0db50d7ACE329C07313a0420502;
        ADMIN_MULTISIG = 0xD9D30ab47c0f096b0AA67e9B8B1624504a63e7FD;
        GUARDIAN_OLD = 0x2559998026796Ca6fd057f3aa66F2d6ecdEd9028;

        // old pool addresses
        TRANCHE_TOKEN_OLD = 0x30baA3BA9D7089fD8D020a994Db75D14CF7eC83b;
        VAULT_OLD = 0xB3AC09cd5201569a821d87446A4aF1b202B10aFd;

        // new deployment addresses
        ROOT_NEW = 0x0000000000000000000000000000000000000000; // TODO Set and make constant
        GUARDIAN_NEW = 0x0000000000000000000000000000000000000000; // TODO Set and make constant
        POOLMANAGER_NEW = 0x0000000000000000000000000000000000000000; // TODO Set and make constant
        RESTRICTIONMANAGER_NEW = 0x0000000000000000000000000000000000000000; // TODO Set and make constant

        // information to deploy the new tranche token & liquidity pool to be able to migrate the tokens
        POOL_ID = 4139607887;
        TRANCHE_ID = 0x97aa65f23e7be09fcd62d0554d2e9273;
        DECIMALS = 6;
        NAME = "Anemoy Liquid Treasury Fund 1";
        SYMBOL = "LTF";

        NAME_OLD = "DEPRECATED";
        SYMBOL_OLD = "DEPRECATED";

        memberlistMembers = [
            0xd595E1483c507E74E2E6A3dE8e7D08d8f6F74936,
            0xeF08Bb6F5F9494faf2316402802e54089E6322eb,
            0x30d3bbAE8623d0e9C0db5c27B82dCDA39De40997,
            0xeEDC395aAAb05e5fb6130A8C5AEbAE48E7739B78,
            0x2923c1B5313F7375fdaeE80b7745106deBC1b53E,
            0x14FFe68D005e58f08c27dC0c999f75639682276c,
            0x86552B8d4F4a600D92d516eE8eA8B922EFEcB561
        ];

        validUntil[0xd595E1483c507E74E2E6A3dE8e7D08d8f6F74936] = type(uint64).max;
        validUntil[0xeF08Bb6F5F9494faf2316402802e54089E6322eb] = 2017150288;
        validUntil[0x30d3bbAE8623d0e9C0db5c27B82dCDA39De40997] = 2017323212;
        validUntil[0xeEDC395aAAb05e5fb6130A8C5AEbAE48E7739B78] = 3745713365;
        validUntil[0x2923c1B5313F7375fdaeE80b7745106deBC1b53E] = 2031229099;
        validUntil[0x14FFe68D005e58f08c27dC0c999f75639682276c] = 2035299660;
        validUntil[0x86552B8d4F4a600D92d516eE8eA8B922EFEcB561] = 2037188261;
    }
}
