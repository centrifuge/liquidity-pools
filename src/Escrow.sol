// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2017, 2018, 2019 dbrock, rain, mrchico
// Copyright (C) 2021 Dai Foundation
pragma solidity ^0.8.18;

import "./auth/auth.sol";

interface ApproveLike {
    function approve(address, uint256) external;
}

contract Escrow is Auth {
    event Approve(address indexed token, address indexed spender, uint256 value);

    constructor() {
        wards[msg.sender] = 1;
        emit Rely(msg.sender);
    }

    // --- Token approvals ---
    function approve(address token, address spender, uint256 value) external auth {
        emit Approve(token, spender, value);

        ApproveLike(token).approve(spender, value);
    }
}
