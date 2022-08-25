// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.7.6;

interface MemberlistLike {
    function updateMember(address usr, uint validUntil) external;
    function members(address usr) external view returns (uint);
}

contract Memberlist {

    uint public constant minimumDelay = 7 days;

    mapping (address => uint) public members;

    // --- Auth ---
    mapping (address => uint) public wards;
    function rely(address usr) public auth { wards[usr] = 1; }
    function deny(address usr) public auth { wards[usr] = 0; }
    modifier auth { require(wards[msg.sender] == 1); _; }

    constructor() {
        wards[msg.sender] = 1;
    }

    function updateMember(address usr, uint validUntil) public auth {
        require((safeAdd(block.timestamp, minimumDelay)) < validUntil, "invalid-validUntil");
        members[usr] = validUntil;
     }

    function updateMembers(address[] memory users, uint validUntil) public auth {
        for (uint i = 0; i < users.length; i++) {
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

    // --- MATH ---
    function safeAdd(uint x, uint y) internal pure returns (uint z) {
        require((z = x + y) >= x, "math-add-overflow");
    }
}