// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import {MigratedLiquidityPool} from "./MigratedLiquidityPool.sol";
import {MigratedRestrictionManager} from "./MigratedRestrictionManager.sol";
import {Auth} from "./Auth.sol";

interface RootLike {
    function escrow() external view returns (address);
}

contract MigratedLiquidityPoolFactory is Auth {
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
            new MigratedLiquidityPool(poolId, trancheId, currency, trancheToken, escrow, investmentManager);

        liquidityPool.rely(root);
        for (uint256 i = 0; i < wards_.length; i++) {
            liquidityPool.rely(wards_[i]);
        }
        liquidityPool.deny(address(this));
        return address(liquidityPool);
    }
}

contract MigratedRestrictionManagerFactory is Auth {
    address immutable root;

    constructor(address _root) {
        root = _root;

        wards[msg.sender] = 1;
        emit Rely(msg.sender);
    }

    function newRestrictionManager(address token, address[] calldata restrictionManagerWards)
        public
        auth
        returns (address)
    {
        RestrictionManager restrictionManager = new MigratedRestrictionManager(token);

        restrictionManager.updateMember(RootLike(root).escrow(), type(uint256).max);

        restrictionManager.rely(root);
        for (uint256 i = 0; i < restrictionManagerWards.length; i++) {
            restrictionManager.rely(restrictionManagerWards[i]);
        }
        restrictionManager.deny(address(this));

        return (address(restrictionManager));
    }
}
