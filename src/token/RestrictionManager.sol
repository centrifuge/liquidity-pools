// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import {Auth} from "./../util/Auth.sol";

interface MemberlistLike {
    function updateMember(address user, uint256 validUntil) external;
    function members(address user) external view returns (uint256);
    function hasMember(address user) external view returns (bool);
}

/// @title  Restriction Manager
/// @notice ERC1404 based contract that checks transfer restrictions.
contract RestrictionManager is Auth {
    uint8 public constant SUCCESS_CODE = 0;
    uint8 public constant DESTINATION_NOT_A_MEMBER_RESTRICTION_CODE = 1;
    string public constant SUCCESS_MESSAGE = "RestrictionManager/transfer-allowed";
    string public constant DESTINATION_NOT_A_MEMBER_RESTRICTION_MESSAGE = "RestrictionManager/destination-not-a-member";

    mapping(address => uint256) public members;

    constructor() {
        wards[msg.sender] = 1;
        emit Rely(msg.sender);
    }

    // --- ERC1404 implementation ---
    function detectTransferRestriction(address from, address to, uint256 value) public view returns (uint8) {
        if (!hasMember(to)) {
            return DESTINATION_NOT_A_MEMBER_RESTRICTION_CODE;
        }

        return SUCCESS_CODE;
    }

    function messageForTransferRestriction(uint8 restrictionCode) public view returns (string memory) {
        if (restrictionCode == DESTINATION_NOT_A_MEMBER_RESTRICTION_CODE) {
            return DESTINATION_NOT_A_MEMBER_RESTRICTION_MESSAGE;
        }

        return SUCCESS_MESSAGE;
    }

    // --- Checking members ---
    function member(address user) public view {
        require((members[user] >= block.timestamp), "RestrictionManager/destination-not-a-member");
    }

    function hasMember(address user) public view returns (bool) {
        if (members[user] >= block.timestamp) {
            return true;
        }
        return false;
    }

    // --- Updating members ---
    function updateMember(address user, uint256 validUntil) public auth {
        require(block.timestamp <= validUntil, "RestrictionManager/invalid-valid-until");
        members[user] = validUntil;
    }

    function updateMembers(address[] memory users, uint256 validUntil) public auth {
        uint256 userLength = users.length;
        for (uint256 i = 0; i < userLength; i++) {
            updateMember(users[i], validUntil);
        }
    }
}
