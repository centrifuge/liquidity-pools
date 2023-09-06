// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import {Auth} from "./util/Auth.sol";
import {SafeTransferLib} from "./util/SafeTransferLib.sol";

interface ApproveLike {
    function approve(address, uint256) external returns (bool);
}

/// @title  Escrow
/// @notice Escrow contract that holds tokens.
///         Only wards can approve funds to be taken out.
contract Escrow is Auth {
    event Approve(address indexed token, address indexed spender, uint256 value);

    constructor() {
        wards[msg.sender] = 1;
        emit Rely(msg.sender);
    }

    // --- Token approvals ---
    function approve(address token, address spender, uint256 value) external auth {
        SafeTransferLib.safeApprove(token, spender, value);
        emit Approve(token, spender, value);
    }
}
