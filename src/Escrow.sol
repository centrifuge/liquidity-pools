// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2017, 2018, 2019 dbrock, rain, mrchico
// Copyright (C) 2021 Dai Foundation
pragma solidity ^0.8.18;

interface ApproveLike {
    function approve(address, uint256) external;
}

contract ConnectorEscrow {
    mapping(address => uint256) public wards;

    // --- Events ---
    event Rely(address indexed usr);
    event Deny(address indexed usr);

    event Approve(address indexed token, address indexed spender, uint256 value);

    constructor() {
        wards[msg.sender] = 1;
        emit Rely(msg.sender);
    }

    modifier auth() {
        require(wards[msg.sender] == 1, "ConnectorEscrow/not-authorized");
        _;
    }

    // --- Administration ---
    function rely(address usr) external auth {
        wards[usr] = 1;
        emit Rely(usr);
    }

    function deny(address usr) external auth {
        wards[usr] = 0;
        emit Deny(usr);
    }

    // --- Token approvals ---
    function approve(address token, address spender, uint256 value) external auth {
        emit Approve(token, spender, value);

        ApproveLike(token).approve(spender, value);
    }
}
