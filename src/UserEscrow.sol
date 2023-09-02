// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.21;

import {Auth} from "./util/Auth.sol";

interface TransferLike {
    function transferFrom(address, address, uint256) external returns (bool);
    function transfer(address, uint256) external returns (bool);
}

/**
 * @dev Escrow contract that holds tokens for specific destinations.
 * Ensures that once tokens are transferred in, they can only be
 * transferred out to the pre-chosen destinations, by wards.
 */
contract UserEscrow is Auth {
    event TransferIn(address indexed token, address indexed source, address indexed destination, uint256 amount);
    event TransferOut(address indexed token, address indexed destination, uint256 amount);

    mapping(address => mapping(address => uint256)) destinations; // map by token and destination

    constructor() {
        wards[msg.sender] = 1;
        emit Rely(msg.sender);
    }

    // --- Token approvals ---
    function transferIn(address token, address source, address destination, uint256 amount) external auth {
        destinations[token][destination] = amount;

        require(TransferLike(token).transferFrom(source, address(this), amount), "UserEscrow/transfer-failed");
        emit TransferIn(token, source, destination, amount);
    }

    function transferOut(address token, address destination, uint256 amount) external auth {
        require(destinations[token][destination] >= amount, "UserEscrow/transfer-failed");
        destinations[token][destination] -= amount;

        require(TransferLike(token).transfer(destination, amount), "UserEscrow/transfer-failed");
        emit TransferOut(token, destination, amount);
    }
}
