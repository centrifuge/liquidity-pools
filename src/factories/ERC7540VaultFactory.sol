// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import {ERC7540Vault} from "../ERC7540Vault.sol";
import {Auth} from "../Auth.sol";

interface ERC7540VaultFactoryLike {
    function newVault(
        uint64 poolId,
        bytes16 trancheId,
        address currency,
        address trancheToken,
        address escrow,
        address investmentManager,
        address[] calldata wards_
    ) external returns (address);
    function denyVault(address vault, address investmentManager) external;
}

interface AuthLike {
    function rely(address) external;
    function deny(address) external;
}

/// @title  ERC7540 Vault Factory
/// @dev    Utility for deploying new liquidity pool contracts
contract ERC7540VaultFactory is Auth {
    address public immutable root;

    constructor(address _root) {
        root = _root;

        wards[msg.sender] = 1;
        emit Rely(msg.sender);
    }

    function newVault(
        uint64 poolId,
        bytes16 trancheId,
        address currency,
        address trancheToken,
        address escrow,
        address investmentManager,
        address[] calldata wards_
    ) public auth returns (address) {
        ERC7540Vault vault = new ERC7540Vault(poolId, trancheId, currency, trancheToken, escrow, investmentManager);

        vault.rely(root);
        for (uint256 i = 0; i < wards_.length; i++) {
            vault.rely(wards_[i]);
        }

        AuthLike(investmentManager).rely(address(vault));

        vault.deny(address(this));
        return address(vault);
    }

    function denyVault(address vault, address investmentManager) public auth {
        AuthLike(investmentManager).deny(address(vault));
    }
}
