// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.18;

import {Auth} from "./util/Auth.sol";

interface ApproveLike {
    function approve(address, uint256) external returns (bool);
}

contract Escrow is Auth {
    event Approve(address indexed token, address indexed spender, uint256 value);

    constructor() {
        wards[msg.sender] = 1;
        emit Rely(msg.sender);
    }

    // --- Token approvals ---
    function approve(address token, address spender, uint256 value) external auth {
        require(ApproveLike(token).approve(spender, value), "Escrow/approve-failed");
        emit Approve(token, spender, value);
    }
}
