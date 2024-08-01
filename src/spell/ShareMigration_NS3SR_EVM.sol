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
        TRANCHE_TOKEN_OLD = 0x8d6825d576827bf8E87a17CDD5684E771fbe221C;
        VAULT_OLD = 0x0d3992B5B5c4fd1c08F73DEd3939e242f0ABd78c;

        // new deployment addresses
        ROOT_NEW = 0x0000000000000000000000000000000000000000;
        GUARDIAN_NEW = 0x0000000000000000000000000000000000000000;
        POOLMANAGER_NEW = 0x0000000000000000000000000000000000000000;
        RESTRICTIONMANAGER_NEW = 0x0000000000000000000000000000000000000000;

        // information to deploy the new tranche token & liquidity pool to be able to migrate the tokens
        POOL_ID = 1615768079;
        TRANCHE_ID = 0xda64aae939e4d3a981004619f1709d8f;
        DECIMALS = 6;
        NAME = "New Silver Series 3 Senior";
        SYMBOL = "NS3SR";

        NAME_OLD = "DEPRECATED";
        SYMBOL_OLD = "DEPRECATED";

        memberlistMembers = [0xd595E1483c507E74E2E6A3dE8e7D08d8f6F74936, 0xbe19e6AdF267248beE015dd3fbBa363E12ca8cE6];

        validUntil[0xd595E1483c507E74E2E6A3dE8e7D08d8f6F74936] = type(uint64).max;
        validUntil[0xbe19e6AdF267248beE015dd3fbBa363E12ca8cE6] = 4869492494;
    }
}
