// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import {LiquidityPool} from "../LiquidityPool.sol";
import {TrancheToken} from "../token/Tranche.sol";
import {Memberlist} from "../token/Memberlist.sol";
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
        address[] calldata memberlistWards
    ) external returns (address);
}

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
        address[] calldata memberlistWards
    ) public auth returns (address) {
        address memberlist = _newMemberlist(memberlistWards);

        // Salt is hash(poolId + trancheId)
        // same tranche token address on every evm chain
        bytes32 salt = keccak256(abi.encodePacked(poolId, trancheId));

        TrancheToken token = new TrancheToken{salt: salt}(decimals);

        token.file("name", name);
        token.file("symbol", symbol);
        token.file("memberlist", memberlist);

        token.rely(root);
        for (uint256 i = 0; i < trancheTokenWards.length; i++) {
            token.rely(trancheTokenWards[i]);
        }
        token.deny(address(this));

        return address(token);
    }

    function _newMemberlist(address[] calldata memberlistWards) internal returns (address memberList) {
        Memberlist memberlist = new Memberlist();

        memberlist.updateMember(RootLike(root).escrow(), type(uint256).max);

        memberlist.rely(root);
        for (uint256 i = 0; i < memberlistWards.length; i++) {
            memberlist.rely(memberlistWards[i]);
        }
        memberlist.deny(address(this));

        return (address(memberlist));
    }
}
