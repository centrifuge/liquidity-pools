pragma solidity 0.8.26;

import {MigrationSpellBase} from "src/spell/MigrationSpellBase.sol";

interface ITrancheOld {
    function authTransferFrom(address from, address to, uint256 value) external returns (bool);
}

contract MigrationSpell is MigrationSpellBase {
    constructor() {
        NETWORK = "celo-mainnet";
        // old deployment addresses
        ROOT_OLD = 0x498016d30Cd5f0db50d7ACE329C07313a0420502;
        ADMIN_MULTISIG = 0x2464f95F6901233bF4a0130A3611d5B4CBd83195;
        GUARDIAN_OLD = 0x2559998026796Ca6fd057f3aa66F2d6ecdEd9028;

        // old pool addresses
        VAULT_OLD = 0xa0872E8D2975483b2Ab4Afcee729133D8666F6f5;

        // new deployment addresses
        ROOT_NEW = 0x89e0E9ef81966BfA7D64BBE76394D36014a685c3;
        GUARDIAN_NEW = 0x32043A41F4be198C4f6590312F7A7b91624Cab57;
        POOLMANAGER_NEW = 0xa3Ce97352C1469884EEF3547Ec9362329FE78Cf0;
        RESTRICTIONMANAGER_NEW = 0x9d5fbC48077863d63a883f44F66aCCde72A9D4e2;

        // information to deploy the new tranche token & liquidity pool to be able to migrate the tokens
        NAME = "Anemoy Liquid Treasury Fund 1";
        SYMBOL = "LTF";

        NAME_OLD = "LTF (deprecated)";
        SYMBOL_OLD = "LTF-DEPRECATED";

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
