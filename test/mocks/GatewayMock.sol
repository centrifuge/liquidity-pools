// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import "./Mock.sol";

contract GatewayMock is Mock {
    constructor() {}

    // --- Incoming ---
    function handle(bytes calldata message) public {
        values_bytes["handle_message"] = message;
    }

    // --- Outgoing ---
    function transferTrancheTokensToCentrifuge(
        uint64 poolId,
        bytes16 trancheId,
        address sender,
        bytes32 destinationAddress,
        uint128 amount
    ) public {
        values_uint64["poolId"] = poolId;
        values_bytes16["trancheId"] = trancheId;
        values_address["sender"] = sender;
        values_bytes32["destinationAddress"] = destinationAddress; // why bytes here?
        values_uint128["amount"] = amount;
    }

    function transferTrancheTokensToEVM(
        uint64 poolId,
        bytes16 trancheId,
        address sender,
        uint64 destinationChainId,
        address destinationAddress,
        uint128 amount
    ) public {
        values_uint64["poolId"] = poolId;
        values_bytes16["trancheId"] = trancheId;
        values_address["sender"] = sender;
        values_uint64["destinationChainId"] = destinationChainId;
        values_address["destinationAddress"] = destinationAddress;
        values_uint128["amount"] = amount;
    }

    function transfer(uint128 token, address sender, bytes32 receiver, uint128 amount) public {
        values_uint128["token"] = token;
        values_address["sender"] = sender;
        values_bytes32["receiver"] = receiver;
        values_uint128["amount"] = amount;
    }

    function increaseInvestOrder(uint64 poolId, bytes16 trancheId, address investor, uint128 currency, uint128 amount)
        public
    {
        values_uint64["poolId"] = poolId;
        values_bytes16["trancheId"] = trancheId;
        values_address["investor"] = investor;
        values_uint128["currency"] = currency;
        values_uint128["amount"] = amount;
    }

    function decreaseInvestOrder(uint64 poolId, bytes16 trancheId, address investor, uint128 currency, uint128 amount)
        public
    {
        values_uint64["poolId"] = poolId;
        values_bytes16["trancheId"] = trancheId;
        values_address["investor"] = investor;
        values_uint128["currency"] = currency;
        values_uint128["amount"] = amount;
    }

    function increaseRedeemOrder(uint64 poolId, bytes16 trancheId, address investor, uint128 currency, uint128 amount)
        public
    {
        values_uint64["poolId"] = poolId;
        values_bytes16["trancheId"] = trancheId;
        values_address["investor"] = investor;
        values_uint128["currency"] = currency;
        values_uint128["amount"] = amount;
    }

    function collectInvest(uint64 poolId, bytes16 trancheId, address investor, uint128 currency) public {
        values_uint64["poolId"] = poolId;
        values_bytes16["trancheId"] = trancheId;
        values_address["investor"] = investor;
        values_uint128["currency"] = currency;
    }

    function collectRedeem(uint64 poolId, bytes16 trancheId, address investor, uint128 currency) public {
        values_uint64["poolId"] = poolId;
        values_bytes16["trancheId"] = trancheId;
        values_address["investor"] = investor;
        values_uint128["currency"] = currency;
    }

    function cancelInvestOrder(uint64 poolId, bytes16 trancheId, address investor, uint128 currency) public {
        values_uint64["poolId"] = poolId;
        values_bytes16["trancheId"] = trancheId;
        values_address["investor"] = investor;
        values_uint128["currency"] = currency;
    }

    function cancelRedeemOrder(uint64 poolId, bytes16 trancheId, address investor, uint128 currency) public {
        values_uint64["poolId"] = poolId;
        values_bytes16["trancheId"] = trancheId;
        values_address["investor"] = investor;
        values_uint128["currency"] = currency;
    }
}
