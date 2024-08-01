pragma solidity 0.8.26;

import {MigrationSpellBase} from "src/spell/MigrationSpellBase.sol";

interface ITrancheOld {
    function authTransferFrom(address from, address to, uint256 value) external returns (bool);
}

contract MigrationSpell is MigrationSpellBase {
    constructor() {
        NETWORK = "celo-mainnet";
        // old deployment addresses
        CURRENCY = 0x37f750B7cC259A2f741AF45294f6a16572CF5cAd;
        CURRENCY_ID = 242333941209166991950178742833476896420;
        ESCROW_OLD = 0xd595E1483c507E74E2E6A3dE8e7D08d8f6F74936;
        INVESTMENTMANAGER_OLD = 0xbBF0AB988691dB1892ADaF7F0eF560Ca4c6DD73A;
        ROOT_OLD = 0x498016d30Cd5f0db50d7ACE329C07313a0420502;
        ADMIN_MULTISIG = 0x2464f95F6901233bF4a0130A3611d5B4CBd83195;
        GUARDIAN_OLD = 0x2559998026796Ca6fd057f3aa66F2d6ecdEd9028;

        // old pool addresses
        TRANCHE_TOKEN_OLD = 0x6D2B49608a716E30bC7aBcFE00181bF261Bf6FC5;
        VAULT_OLD = 0xa0872E8D2975483b2Ab4Afcee729133D8666F6f5;

        // new deployment addresses
        ROOT_NEW = 0x0000000000000000000000000000000000000000;
        GUARDIAN_NEW = 0x0000000000000000000000000000000000000000;
        POOLMANAGER_NEW = 0x0000000000000000000000000000000000000000;
        RESTRICTIONMANAGER_NEW = 0x0000000000000000000000000000000000000000;

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
            0x0D9E269ECc319BAE886Dd8c8B98F7B89269C2B1B,
            0x6854f6671c1934c77cf7592B0b264f762614014E
        ];

        validUntil[0xd595E1483c507E74E2E6A3dE8e7D08d8f6F74936] = type(uint64).max;
        validUntil[0x0D9E269ECc319BAE886Dd8c8B98F7B89269C2B1B] = 2020186137;
        validUntil[0x6854f6671c1934c77cf7592B0b264f762614014E] = 2020262249;
    }
}
