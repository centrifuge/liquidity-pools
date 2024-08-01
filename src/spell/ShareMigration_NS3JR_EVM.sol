pragma solidity 0.8.26;

import {MigrationSpellBase} from "src/spell/MigrationSpellBase.sol";

interface ITrancheOld {
    function authTransferFrom(address from, address to, uint256 value) external returns (bool);
}

contract MigrationSpell is MigrationSpellBase {
    constructor() {
        NETWORK = "ethereum-mainnet";
        // old deployment addresses
        CURRENCY = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
        CURRENCY_ID = 242333941209166991950178742833476896417;
        ESCROW_OLD = 0xd595E1483c507E74E2E6A3dE8e7D08d8f6F74936;
        INVESTMENTMANAGER_OLD = 0xbBF0AB988691dB1892ADaF7F0eF560Ca4c6DD73A;
        ROOT_OLD = 0x498016d30Cd5f0db50d7ACE329C07313a0420502;
        ADMIN_MULTISIG = 0xD9D30ab47c0f096b0AA67e9B8B1624504a63e7FD;
        GUARDIAN_OLD = 0x2559998026796Ca6fd057f3aa66F2d6ecdEd9028;

        // old pool addresses
        TRANCHE_TOKEN_OLD = 0xeC9106d0BA35B2228d7Ef3a7c3e7400Cd0f430BD;
        VAULT_OLD = 0xd0C7E8C9b0c82b74771AE13e184432240A3a2F54;

        // new deployment addresses
        ROOT_NEW = 0x0000000000000000000000000000000000000000;
        GUARDIAN_NEW = 0x0000000000000000000000000000000000000000;
        POOLMANAGER_NEW = 0x0000000000000000000000000000000000000000;
        RESTRICTIONMANAGER_NEW = 0x0000000000000000000000000000000000000000;

        // information to deploy the new tranche token & liquidity pool to be able to migrate the tokens
        POOL_ID = 1615768079;
        TRANCHE_ID = 0x6756e091ae798a8e51e12e27ee8facdf;
        DECIMALS = 6;
        NAME = "New Silver Series 3 Junior";
        SYMBOL = "NS3JR";

        NAME_OLD = "DEPRECATED";
        SYMBOL_OLD = "DEPRECATED";

        memberlistMembers = [
            0xd595E1483c507E74E2E6A3dE8e7D08d8f6F74936,
            0x32f5eF78AA9C7b8882D748331AdcFe0dfA4f1a14
        ];

        validUntil[0xd595E1483c507E74E2E6A3dE8e7D08d8f6F74936] = type(uint64).max;
        validUntil[0x32f5eF78AA9C7b8882D748331AdcFe0dfA4f1a14] = 2030638540;
    }
}
