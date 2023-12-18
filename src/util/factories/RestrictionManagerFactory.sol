// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import {RestrictionManager} from "src/token/RestrictionManager.sol";
import {Auth} from "src/util/Auth.sol";

interface RootLike {
    function escrow() external view returns (address);
}

interface RestrictionManagerFactoryLike {
    function newRestrictionManager(uint8 restrictionSet, address token, address[] calldata restrictionManagerWards)
        external
        returns (address);
}

/// @title  Restriction Manager Factory
/// @dev    Utility for deploying new restriction manager contracts
contract RestrictionManagerFactory is Auth {
    address immutable root;

    constructor(address _root) {
        root = _root;

        wards[msg.sender] = 1;
        emit Rely(msg.sender);
    }

    function newRestrictionManager(uint8, address token, address[] calldata restrictionManagerWards)
        public
        auth
        returns (address)
    {
        RestrictionManager restrictionManager = new RestrictionManager(token);

        restrictionManager.updateMember(RootLike(root).escrow(), type(uint256).max);

        restrictionManager.rely(root);
        restrictionManager.rely(token);
        for (uint256 i = 0; i < restrictionManagerWards.length; i++) {
            restrictionManager.rely(restrictionManagerWards[i]);
        }
        restrictionManager.deny(address(this));

        return (address(restrictionManager));
    }
}
