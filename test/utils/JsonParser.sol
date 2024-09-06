// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.26;

import "forge-std/StdJson.sol";

library JsonParser {
    using stdJson for string;

    function asAddress(string memory json, string memory key) public pure returns (address) {
        return abi.decode(json.parseRaw(key), (address));
    }

    function asUint(string memory json, string memory key) public pure returns (uint256) {
        return abi.decode(json.parseRaw(key), (uint256));
    }

    function asBool(string memory json, string memory key) public pure returns (bool) {
        return abi.decode(json.parseRaw(key), (bool));
    }
}
