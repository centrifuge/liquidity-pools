// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.18;

import "./util/Auth.sol";

interface TransferLike {
    function transferFrom(address, address, uint256) external;
}

contract UserEscrow is Auth {
    event Approve(address indexed token, address indexed spender, uint256 amount);
    event Transfer(address indexed user, uint256 amount);

    mapping (address => mapping (address => uint256)) destinations; // map by token and destination

    constructor() {
        wards[msg.sender] = 1;
        emit Rely(msg.sender);
    }

    // --- Token approvals ---
    function approve(address token, address destination, uint256 amount) external auth {
        destinations[token][destination] = amount;
        emit Approve(token, destination, amount);
    }

    function transfer(address token, address destination, uint256 amount) external auth {
        require(destinations[token][destination] >= amount, "UserEscrow/transfer-failed");
        require(TransferLike(token).transferFrom(address(this), destination, amount), "UserEscrow/transfer-failed");

        destinations[token][destination] -= amount;
        emit Transfer(token, destination, amount);
    }
}
