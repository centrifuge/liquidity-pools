// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.7.6;

interface MemberlistLike {
    function updateMember(address usr, uint256 validUntil) external;
    function members(address usr) external view returns (uint256);
}

contract Memberlist {
    mapping(address => uint256) public members;

    // --- Auth ---
    mapping(address => uint256) public wards;

    function rely(address usr) public auth {
        wards[usr] = 1;
    }

    function deny(address usr) public auth {
        wards[usr] = 0;
    }

    modifier auth() {
        require(wards[msg.sender] == 1);
        _;
    }

    // --- Math ---
    function safeAdd(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require((z = x + y) >= x, "math-add-overflow");
    }

    constructor() {
        wards[msg.sender] = 1;
    }

    function updateMember(address usr, uint256 validUntil) public auth {
        require(block.timestamp <= validUntil, "invalid-validUntil");
        members[usr] = validUntil;
    }

    function updateMembers(address[] memory users, uint256 validUntil) public auth {
        for (uint256 i = 0; i < users.length; i++) {
            updateMember(users[i], validUntil);
        }
    }

    function member(address usr) public view {
        require((members[usr] >= block.timestamp), "not-allowed-to-hold-token");
    }

    function hasMember(address usr) public view returns (bool) {
        if (members[usr] >= block.timestamp) {
            return true;
        }
        return false;
    }
}
