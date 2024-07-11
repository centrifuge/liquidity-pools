// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.26;

import {Tranche} from "src/token/Tranche.sol";
import {Auth} from "src/Auth.sol";

interface TrancheFactoryLike {
    function newTranche(
        uint64 poolId,
        bytes16 trancheId,
        string memory name,
        string memory symbol,
        uint8 decimals,
        address[] calldata restrictionManagerWards
    ) external returns (address);
}

/// @title  Tranche Token Factory
/// @dev    Utility for deploying new tranche token contracts
///         Ensures the addresses are deployed at a deterministic address
///         based on the pool id and tranche id.
contract TrancheFactory is Auth, TrancheFactoryLike {
    address public immutable root;

    constructor(address _root, address deployer) {
        root = _root;
        wards[deployer] = 1;
        emit Rely(deployer);
    }

    function newTranche(
        uint64 poolId,
        bytes16 trancheId,
        string memory name,
        string memory symbol,
        uint8 decimals,
        address[] calldata trancheWards
    ) public auth returns (address) {
        // Salt is hash(poolId + trancheId)
        // same tranche token address on every evm chain
        bytes32 salt = keccak256(abi.encodePacked(poolId, trancheId));

        Tranche token = new Tranche{salt: salt}(decimals);

        token.file("name", name);
        token.file("symbol", symbol);

        token.rely(root);
        for (uint256 i = 0; i < trancheWards.length; i++) {
            token.rely(trancheWards[i]);
        }
        token.deny(address(this));

        return address(token);
    }
}
