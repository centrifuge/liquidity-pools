// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import {Auth} from "./Auth.sol";
import {SafeTransferLib} from "./libraries/SafeTransferLib.sol";
import {IEscrow} from "src/interfaces/IEscrow.sol";

/// @title  Escrow
/// @notice Escrow contract that holds tokens.
///         Only wards can approve funds to be taken out.
contract Escrow is Auth, IEscrow {
    constructor(address deployer) {
        wards[deployer] = 1;
        emit Rely(deployer);
    }

    // --- Token approvals ---
    /// @inheritdoc IEscrow
    function approve(address token, address spender, uint256 value) external auth {
        // Approve 0 first for tokens that require this
        SafeTransferLib.safeApprove(token, spender, 0);

        SafeTransferLib.safeApprove(token, spender, value);
        emit Approve(token, spender, value);
    }
}
