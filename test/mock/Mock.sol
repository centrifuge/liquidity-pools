// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import "forge-std/Test.sol";

contract Mock is Test {
    // counting calls
    mapping(bytes32 => uint256) public calls;

    // returns
    mapping(bytes32 => uint128) public values_uint128_return;
    mapping(bytes32 => bool) public values_bool_return;

    // passed parameter
    mapping(bytes32 => uint64) public values_uint64;
    mapping(bytes32 => uint128) public values_uint128;
    mapping(bytes32 => uint256) public values_uint256;
    mapping(bytes32 => address) public values_address;
    mapping(bytes32 => bytes32) public values_bytes16;
    mapping(bytes32 => bytes32) public values_bytes32;
    mapping(bytes32 => bytes) public values_bytes;
    mapping(bytes32 => string) public values_string;

    mapping(bytes32 => bool) method_fail;

    function call(bytes32 name) internal returns (uint256) {
        calls[name]++;
    }

    function setReturn(bytes32 name, uint128 returnValue) public {
        values_uint128_return[name] = returnValue;
    }

    function setReturn(bytes32 name, bool returnValue) public {
        values_bool_return[name] = returnValue;
    }

    function setFail(bytes32 name, bool flag) public {
        method_fail[name] = flag;
    }
}
