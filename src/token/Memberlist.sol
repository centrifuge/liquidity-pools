// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.18;

import {Auth} from "./../util/Auth.sol";

interface MemberlistLike {
    function updateMember(address user, uint256 validUntil) external;
    function members(address user) external view returns (uint256);
}

contract Memberlist is Auth {
    mapping(address => uint256) public members;

    constructor() {
        wards[msg.sender] = 1;
        emit Rely(msg.sender);
    }

    // --- Checking members ---
    function member(address user) public view {
        require((members[user] >= block.timestamp), "Memberlist/not-allowed-to-hold-token");
    }

    function hasMember(address user) public view returns (bool) {
        if (members[user] >= block.timestamp) {
            return true;
        }
        return false;
    }

    // --- Updating members ---
    function updateMember(address user, uint256 validUntil) public auth {
        require(block.timestamp <= validUntil, "Memberlist/invalid-valid-until");
        members[user] = validUntil;
    }

    function updateMembers(address[] memory users, uint256 validUntil) public auth {
        uint256 userLength = users.length;
        for (uint256 i = 0; i < userLength; i++) {
            updateMember(users[i], validUntil);
        }
    }
}
