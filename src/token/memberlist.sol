// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.7.6;

interface MemberlistLike {
    function updateMember(address user, uint256 validUntil) external;
    function members(address user) external view returns (uint256);
}

contract Memberlist {
    mapping(address => uint256) public wards;
    mapping(address => uint256) public members;

    // --- Events ---
    event Rely(address indexed user);
    event Deny(address indexed user);

    constructor() {
        wards[msg.sender] = 1;
        emit Rely(msg.sender);
    }

    modifier auth() {
        require(wards[msg.sender] == 1);
        _;
    }

    // --- Admininistration ---
    function rely(address user) public auth {
        wards[user] = 1;
        emit Rely(msg.sender);
    }

    function deny(address user) public auth {
        wards[user] = 0;
        emit Deny(msg.sender);
    }

    // --- Checking members ---
    function member(address user) public view {
        require((members[user] >= block.timestamp), "not-allowed-to-hold-token");
    }

    function hasMember(address user) public view returns (bool) {
        if (members[user] >= block.timestamp) {
            return true;
        }
        return false;
    }

    // --- Updating members ---
    function updateMember(address user, uint256 validUntil) public auth {
        require(block.timestamp <= validUntil, "invalid-validUntil");
        members[user] = validUntil;
    }

    function updateMembers(address[] memory users, uint256 validUntil) public auth {
        for (uint256 i = 0; i < users.length; i++) {
            updateMember(users[i], validUntil);
        }
    }
}
