pragma solidity 0.8.26;

import {MigrationSpellBase} from "src/spell/MigrationSpellBase.sol";

interface ITrancheOld {
    function authTransferFrom(address from, address to, uint256 value) external returns (bool);
}

contract MigrationSpell is MigrationSpellBase {
    constructor() {
        NETWORK = "ethereum-mainnet";
        // old deployment addresses
        ROOT_OLD = 0x498016d30Cd5f0db50d7ACE329C07313a0420502;
        ADMIN_MULTISIG = 0xD9D30ab47c0f096b0AA67e9B8B1624504a63e7FD;
        GUARDIAN_OLD = 0x2559998026796Ca6fd057f3aa66F2d6ecdEd9028;

        // old pool addresses
        VAULT_OLD = 0x0d3992B5B5c4fd1c08F73DEd3939e242f0ABd78c;

        // new deployment addresses
        ROOT_NEW = 0x0C1fDfd6a1331a875EA013F3897fc8a76ada5DfC;
        GUARDIAN_NEW = 0x09ab10a9c3E6Eac1d18270a2322B6113F4C7f5E8;
        POOLMANAGER_NEW = 0x91808B5E2F6d7483D41A681034D7c9DbB64B9E29;
        RESTRICTIONMANAGER_NEW = 0x4737C3f62Cc265e786b280153fC666cEA2fBc0c0;

        // information to deploy the new tranche token & liquidity pool to be able to migrate the tokens
        NAME = "New Silver Series 3 Senior";
        SYMBOL = "NS3SR";

        NAME_OLD = "NS3SR (deprecated)";
        SYMBOL_OLD = "NS3SR-DEPRECATED";

        memberlistMembers = [0xd595E1483c507E74E2E6A3dE8e7D08d8f6F74936, 0xbe19e6AdF267248beE015dd3fbBa363E12ca8cE6];

        validUntil[0xd595E1483c507E74E2E6A3dE8e7D08d8f6F74936] = type(uint64).max;
        validUntil[0xbe19e6AdF267248beE015dd3fbBa363E12ca8cE6] = 4869492494;
    }
}
