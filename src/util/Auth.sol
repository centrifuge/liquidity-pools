// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) Centrifuge 2020, based on MakerDAO dss https://github.com/makerdao/dss
pragma solidity 0.8.21;

contract Auth {
    mapping(address => uint256) public wards;

    event Rely(address indexed user);
    event Deny(address indexed user);

    function rely(address user) external auth {
        wards[user] = 1;
        emit Rely(user);
    }

    function deny(address user) external auth {
        wards[user] = 0;
        emit Deny(user);
    }

    modifier auth() {
        require(wards[msg.sender] == 1, "Auth/not-authorized");
        _;
    }
}
