// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import {LiquidityPool} from "../LiquidityPool.sol";
import {TrancheToken} from "../token/Tranche.sol";
import {RestrictionManager} from "../token/RestrictionManager.sol";
import {Auth} from "./Auth.sol";

interface RootLike {
    function escrow() external view returns (address);
}

interface LiquidityPoolFactoryLike {
    function newLiquidityPool(
        uint64 poolId,
        bytes16 trancheId,
        address currency,
        address trancheToken,
        address investmentManager,
        address[] calldata wards
    ) external returns (address);
}

/// @title  Liquidity Pool Factory
/// @dev    Utility for deploying new liquidity pool contracts
contract LiquidityPoolFactory is Auth {
    address immutable root;

    constructor(address _root) {
        root = _root;

        wards[msg.sender] = 1;
        emit Rely(msg.sender);
    }

    function newLiquidityPool(
        uint64 poolId,
        bytes16 trancheId,
        address currency,
        address trancheToken,
        address investmentManager,
        address[] calldata wards
    ) public auth returns (address) {
        LiquidityPool liquidityPool = new LiquidityPool(poolId, trancheId, currency, trancheToken, investmentManager);

        liquidityPool.rely(root);
        for (uint256 i = 0; i < wards.length; i++) {
            liquidityPool.rely(wards[i]);
        }
        liquidityPool.deny(address(this));
        return address(liquidityPool);
    }
}

interface TrancheTokenFactoryLike {
    function newTrancheToken(
        uint64 poolId,
        bytes16 trancheId,
        string memory name,
        string memory symbol,
        uint8 decimals,
        address[] calldata trancheTokenWards,
        address[] calldata restrictionManagerWards
    ) external returns (address);
}

/// @title  Tranche Token Factory
/// @dev    Utility for deploying new tranche token contracts
///         Ensures the addresses are deployed at a deterministic address
///         based on the pool id and tranche id.
contract TrancheTokenFactory is Auth {
    address immutable root;

    constructor(address _root) {
        root = _root;

        wards[msg.sender] = 1;
        emit Rely(msg.sender);
    }

    function newTrancheToken(
        uint64 poolId,
        bytes16 trancheId,
        string memory name,
        string memory symbol,
        uint8 decimals,
        address[] calldata trancheTokenWards,
        address[] calldata restrictionManagerWards
    ) public auth returns (address) {
        address restrictionManager = _newRestrictionManager(restrictionManagerWards);

        // Salt is hash(poolId + trancheId)
        // same tranche token address on every evm chain
        bytes32 salt = keccak256(abi.encodePacked(poolId, trancheId));

        TrancheToken token = new TrancheToken{salt: salt}(decimals);

        token.file("name", name);
        token.file("symbol", symbol);
        token.file("restrictionManager", restrictionManager);

        token.rely(root);
        for (uint256 i = 0; i < trancheTokenWards.length; i++) {
            token.rely(trancheTokenWards[i]);
        }
        token.deny(address(this));

        return address(token);
    }

    function _newRestrictionManager(address[] calldata restrictionManagerWards) internal returns (address memberList) {
        RestrictionManager restrictionManager = new RestrictionManager();

        restrictionManager.updateMember(RootLike(root).escrow(), type(uint256).max);

        restrictionManager.rely(root);
        for (uint256 i = 0; i < restrictionManagerWards.length; i++) {
            restrictionManager.rely(restrictionManagerWards[i]);
        }
        restrictionManager.deny(address(this));

        return (address(restrictionManager));
    }
}
