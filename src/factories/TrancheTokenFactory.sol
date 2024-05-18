// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import {TrancheToken01} from "src/token/TrancheToken01.sol";
import {Auth} from "src/Auth.sol";

interface RootLike {
    function escrow() external view returns (address);
}

interface TrancheTokenFactoryLike {
    function newTrancheToken(
        uint64 poolId,
        bytes16 trancheId,
        string memory name,
        string memory symbol,
        uint8 decimals,
        address[] calldata trancheTokenWards,
        uint8 trancheType
    ) external returns (address);
}

/// @title  Tranche Token Factory
/// @dev    Utility for deploying new tranche token contracts
///         Ensures the addresses are deployed at a deterministic address
///         based on the pool id and tranche id.
contract TrancheTokenFactory is Auth {
    address public immutable root;

    constructor(address _root, address deployer) {
        root = _root;
        wards[deployer] = 1;
        emit Rely(deployer);
    }

    function newTrancheToken(
        uint64 poolId,
        bytes16 trancheId,
        string memory name,
        string memory symbol,
        uint8 decimals,
        address[] calldata trancheTokenWards,
        uint8 trancheType
    ) public auth returns (address) {
        require(trancheType == 1, "TrancheTokenFactory/unsupported-tranche-type");

        // Salt is hash(poolId + trancheId)
        // same tranche token address on every evm chain
        bytes32 salt = keccak256(abi.encodePacked(poolId, trancheId));

        TrancheToken01 token = new TrancheToken01{salt: salt}(decimals, RootLike(root).escrow());

        token.file("name", name);
        token.file("symbol", symbol);

        token.rely(root);
        for (uint256 i = 0; i < trancheTokenWards.length; i++) {
            token.rely(trancheTokenWards[i]);
        }
        token.deny(address(this));

        return address(token);
    }
}
