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

    IMessageRecipient public home;

    uint32 immutable CENTRIFUGE_CHAIN_DOMAIN = 3000;
    uint32 immutable NONCE = 1;

    enum Types {
        AddPool
    }

    constructor() {
    }

    function setRouter(address home_) public {
        home = IMessageRecipient(home_);
    }

    function addPool(uint64 poolId) public {
        bytes memory _message = ConnectorMessages.formatAddPool(poolId);
        home.handle(CENTRIFUGE_CHAIN_DOMAIN, NONCE, "1", _message);
    }

    function addTranche(uint64 poolId, bytes16 trancheId, string memory tokenName, string memory tokenSymbol) public {
        bytes memory _message = ConnectorMessages.formatAddTranche(poolId, trancheId, tokenName, tokenSymbol);
        home.handle(CENTRIFUGE_CHAIN_DOMAIN, NONCE, "1", _message);
    }

    function updateMember(uint64 poolId, bytes16 trancheId, address user, uint256 amount) public {
        bytes memory _message = ConnectorMessages.formatUpdateMember(poolId, trancheId, user, amount);
        home.handle(CENTRIFUGE_CHAIN_DOMAIN, NONCE, "1", _message);
    }

    function updateTokenPrice(uint64 poolId, bytes16 trancheId, uint256 price) public {
        bytes memory _message = ConnectorMessages.formatUpdateTokenPrice(poolId, trancheId, price);
        home.handle(CENTRIFUGE_CHAIN_DOMAIN, NONCE, "1", _message);
    }

    function deposit(uint64 poolId, bytes16 trancheId, address user, uint256 amount) public  {
        bytes memory _message = ConnectorMessages.formatTransfer(poolId, trancheId, user, amount);
        home.handle(CENTRIFUGE_CHAIN_DOMAIN, NONCE, "1", _message);
    }

}
