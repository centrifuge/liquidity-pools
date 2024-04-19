// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import {LiquidityPool} from "../LiquidityPool.sol";
import {Auth} from "../Auth.sol";

interface LiquidityPoolFactoryLike {
    function newLiquidityPool(
        uint64 poolId,
        bytes16 trancheId,
        address currency,
        address trancheToken,
        address escrow,
        address investmentManager,
        address[] calldata wards_
    ) external returns (address);
    function denyLiquidityPool(address liquiditiyPool, address investmentManager) external;
}

interface AuthLike {
    function rely(address) external;
    function deny(address) external;
}

/// @title  Liquidity Pool Factory
/// @dev    Utility for deploying new liquidity pool contracts
contract LiquidityPoolFactory is Auth {
    address public immutable root;

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
        address escrow,
        address investmentManager,
        address[] calldata wards_
    ) public auth returns (address) {
        LiquidityPool liquidityPool =
            new LiquidityPool(poolId, trancheId, currency, trancheToken, escrow, investmentManager);

        liquidityPool.rely(root);
        for (uint256 i = 0; i < wards_.length; i++) {
            liquidityPool.rely(wards_[i]);
        }

        AuthLike(investmentManager).rely(address(liquidityPool));

        liquidityPool.deny(address(this));
        return address(liquidityPool);
    }

    function denyLiquidityPool(address liquidityPool, address investmentManager) public auth {
        AuthLike(investmentManager).deny(address(liquidityPool));
    }
}
