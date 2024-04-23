// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import {Auth} from "./../Auth.sol";
import {IERC20} from "../interfaces/IERC20.sol";
import {IRestrictionManager} from "src/interfaces/token/IRestrictionManager.sol";

interface RestrictionManagerLike {
    function updateMember(address user, uint64 validUntil) external;
    function restrictions(address user) external view returns (bool frozen, uint64 validUntil);
    function freeze(address user) external;
    function unfreeze(address user) external;
}

/// @title  Restriction Manager
/// @notice ERC1404 based contract that checks transfer restrictions.
contract RestrictionManager is Auth, IRestrictionManager {
    string internal constant SUCCESS_MESSAGE = "RestrictionManager/transfer-allowed";
    string internal constant SOURCE_IS_FROZEN_MESSAGE = "RestrictionManager/source-is-frozen";
    string internal constant DESTINATION_IS_FROZEN_MESSAGE = "RestrictionManager/destination-is-frozen";
    string internal constant DESTINATION_NOT_A_MEMBER_RESTRICTION_MESSAGE =
        "RestrictionManager/destination-not-a-member";

    uint8 public constant SUCCESS_CODE = 0;
    uint8 public constant SOURCE_IS_FROZEN_CODE = 1;
    uint8 public constant DESTINATION_IS_FROZEN_CODE = 2;
    uint8 public constant DESTINATION_NOT_A_MEMBER_RESTRICTION_CODE = 3;

    IERC20 public immutable token;

    mapping(address => Restrictions) public restrictions;

    constructor(address token_) {
        token = IERC20(token_);

        wards[msg.sender] = 1;
        emit Rely(msg.sender);
    }

    // --- ERC1404 implementation ---
    function detectTransferRestriction(address from, address to, uint256 /* value */ ) public view returns (uint8) {
        if (restrictions[from].frozen == true) {
            return SOURCE_IS_FROZEN_CODE;
        }

        Restrictions memory toRestrictions = restrictions[to];
        if (toRestrictions.frozen == true) {
            return DESTINATION_IS_FROZEN_CODE;
        }

        if (toRestrictions.validUntil < block.timestamp) {
            return DESTINATION_NOT_A_MEMBER_RESTRICTION_CODE;
        }

        return SUCCESS_CODE;
    }

    function messageForTransferRestriction(uint8 restrictionCode) public pure returns (string memory) {
        if (restrictionCode == SOURCE_IS_FROZEN_CODE) {
            return SOURCE_IS_FROZEN_MESSAGE;
        }

        if (restrictionCode == DESTINATION_IS_FROZEN_CODE) {
            return DESTINATION_IS_FROZEN_MESSAGE;
        }

        if (restrictionCode == DESTINATION_NOT_A_MEMBER_RESTRICTION_CODE) {
            return DESTINATION_NOT_A_MEMBER_RESTRICTION_MESSAGE;
        }

        return SUCCESS_MESSAGE;
    }

    // --- Handling freezes ---
    function freeze(address user) public auth {
        require(user != address(0), "RestrictionManager/cannot-freeze-zero-address");
        restrictions[user].frozen = true;
        emit Freeze(user);
    }

    function unfreeze(address user) public auth {
        restrictions[user].frozen = false;
        emit Unfreeze(user);
    }

    // --- Managing members ---
    function updateMember(address user, uint64 validUntil) public auth {
        require(block.timestamp <= validUntil, "RestrictionManager/invalid-valid-until");
        restrictions[user].validUntil = validUntil;

        emit UpdateMember(user, validUntil);
    }

    // --- Misc ---
    function afterTransfer(address, /* from */ address, /* to */ uint256 /* value */ ) public virtual auth {}
    function afterMint(address, /* to */ uint256 /* value */ ) public virtual auth {}
}
