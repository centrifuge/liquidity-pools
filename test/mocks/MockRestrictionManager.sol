// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import "test/mocks/Mock.sol";
import "src/token/RestrictionManager.sol";

contract MockRestrictionManager is RestrictionManager, Mock {
    constructor(address token_) RestrictionManager(token_) {}

    // --- Misc ---
    function afterTransfer(address from, address to, uint256 amount) public override auth {
        values_address["transfer_from"] = from;
        values_address["transfer_to"] = to;
        values_uint256["transfer_amount"] = amount;
    }

    function afterMint(address to, uint256 amount) public override auth {
        values_address["mint_to"] = to;
        values_uint256["mint_amount"] = amount;
    }
}
