// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import {Auth} from "./util/Auth.sol";
import {SafeTransferLib} from "./util/SafeTransferLib.sol";

interface ERC20Like {
    function allowance(address owner, address spender) external view returns (uint256);
}

/// @title  User Escrow
/// @notice Escrow contract that holds tokens for specific destinations.
///         Ensures that once tokens are transferred in, they can only be
///         transferred out to the pre-chosen destinations, by wards.
contract UserEscrow is Auth {
    event TransferIn(address indexed token, address indexed source, address indexed destination, uint256 amount);
    event TransferOut(address indexed token, address indexed destination, uint256 amount);

    /// @dev Map by token and destination
    mapping(address => mapping(address => uint256)) destinations;

    constructor() {
        wards[msg.sender] = 1;
        emit Rely(msg.sender);
    }

    // --- Token transfers ---
    function transferIn(address token, address source, address destination, uint256 amount) external auth {
        destinations[token][destination] += amount;

        SafeTransferLib.safeTransferFrom(token, source, address(this), amount);
        emit TransferIn(token, source, destination, amount);
    }

    function transferOut(address token, address destination, address receiver, uint256 amount) external auth {
        require(destinations[token][destination] >= amount, "UserEscrow/transfer-failed");
        require(
            receiver == destination || (ERC20Like(token).allowance(destination, receiver) >= amount),
            "UserEscrow/receiver-has-no-allowance"
        );
        destinations[token][destination] -= amount;

        SafeTransferLib.safeTransfer(token, receiver, amount);
        emit TransferOut(token, receiver, amount);
    }
}
