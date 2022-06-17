// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.7.6;

import { RestrictedToken } from "./restricted.sol";

interface RestrictedTokenFactoryLike {
    function newRestrictedToken(string calldata, string calldata) external returns (address);
}

contract RestrictedTokenFactory {
    function newRestrictedToken(string memory symbol, string memory name) public returns (address) {
        RestrictedToken token = new RestrictedToken(symbol, name);
        token.rely(msg.sender);
        token.deny(address(this));
        return address(token);
    }
}