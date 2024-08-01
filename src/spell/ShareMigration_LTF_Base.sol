pragma solidity 0.8.26;

import {MigrationSpellBase} from "src/spell/MigrationSpellBase.sol";

interface ITrancheOld {
    function authTransferFrom(address from, address to, uint256 value) external returns (bool);
}

contract MigrationSpell is MigrationSpellBase {
    constructor() {
        NETWORK = "base-mainnet";
        // old deployment addresses
        CURRENCY_ID = 242333941209166991950178742833476896418;
        ROOT_OLD = 0x498016d30Cd5f0db50d7ACE329C07313a0420502;
        ADMIN_MULTISIG = 0x8b83962fB9dB346a20c95D98d4E312f17f4C0d9b;
        GUARDIAN_OLD = 0x2559998026796Ca6fd057f3aa66F2d6ecdEd9028;

        // old pool addresses
        VAULT_OLD = 0xa0872E8D2975483b2Ab4Afcee729133D8666F6f5;

        // new deployment addresses
        ROOT_NEW = 0x468CBaA7b44851C2426b58190030162d18786b6d;
        GUARDIAN_NEW = 0xA0e3A5709995eF9900ab0F7FA070567Fe89d9e18;
        POOLMANAGER_NEW = 0x7829E5ca4286Df66e9F58160544097dB517a3B8c;
        RESTRICTIONMANAGER_NEW = 0xd35ec9Bd13bC4483D47c850298D5C285C8D1Ec22;

        // information to deploy the new tranche token & liquidity pool to be able to migrate the tokens
        NAME = "Anemoy Liquid Treasury Fund 1";
        SYMBOL = "LTF";

        NAME_OLD = "DEPRECATED";
        SYMBOL_OLD = "DEPRECATED";

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
