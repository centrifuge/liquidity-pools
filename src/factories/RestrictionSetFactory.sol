// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import {RestrictionSet01} from "src/token/RestrictionSet01.sol";
import {Auth} from "src/Auth.sol";

interface RootLike {
    function escrow() external view returns (address);
}

interface RestrictionSetFactoryLike {
    function newRestrictionSet(uint8 restrictionSet, address token, address[] calldata restrictionSetWards)
        external
        returns (address);
}

/// @title  Restriction Set Factory
/// @dev    Utility for deploying new restriction set contracts
contract RestrictionSetFactory is Auth {
    address immutable root;

    constructor(address _root) {
        root = _root;

        wards[msg.sender] = 1;
        emit Rely(msg.sender);
    }

    function newRestrictionSet(uint8, /* restrictionSet */ address token, address[] calldata restrictionSetWards)
        public
        auth
        returns (address)
    {
        RestrictionSet01 restrictionSet = new RestrictionSet01(token, RootLike(root).escrow());

        restrictionSet.rely(root);
        restrictionSet.rely(token);
        for (uint256 i = 0; i < restrictionSetWards.length; i++) {
            restrictionSet.rely(restrictionSetWards[i]);
        }
        restrictionSet.deny(address(this));

        return (address(restrictionSet));
    }
}
