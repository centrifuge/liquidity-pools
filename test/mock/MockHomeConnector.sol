// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.7.6;
pragma abicoder v2;

import {TypedMemView} from "@summa-tx/memview-sol/contracts/TypedMemView.sol";
import {IMessageRecipient} from "@nomad-xyz/contracts-core/contracts/interfaces/IMessageRecipient.sol";
import {ConnectorMessages} from "src/Messages.sol";
import "forge-std/Test.sol";

contract MockHomeConnector is Test {
    using TypedMemView for bytes;
    using TypedMemView for bytes29;
    using ConnectorMessages for bytes29;

    IMessageRecipient public immutable home;

    uint32 immutable CENTRIFUGE_CHAIN_DOMAIN = 3000;

    uint32 immutable NONCE = 1;

    enum Types {
        AddPool
    }

    constructor(address home_) {
        home = IMessageRecipient(home_);
    }

    function addPool(uint64 poolId) public returns (bool) {
        bytes memory _message = ConnectorMessages.formatAddPool(poolId);
        home.handle(CENTRIFUGE_CHAIN_DOMAIN, NONCE, "1", _message);
        return true;
    }
}
