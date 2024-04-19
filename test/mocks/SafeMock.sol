// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

contract SafeMock is Mock {
    constructor(address[] memory owners, uint256 threshold) {
        values_uint256["threshold"] = threshold;
        for (uint256 i = 0; i < owners.length; i++) {
            addOwner(owners[i]);
        }
    }

    function addOwner(address owner) public {
        values_uint256["owners"][owner] = 1;
    }

    function removeOwner(address owner) public {
        values_uint256["owners"][owner] = 0;
    }

    function isOwner(address owner) public view returns (bool) {
        return values_uint256["owners"][owner] == 1;
    }
}