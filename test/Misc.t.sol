// // SPDX-License-Identifier: AGPL-3.0-only
// pragma solidity 0.8.21;
// pragma abicoder v2;

// import {Messages} from "src/Messages.sol";
// import "forge-std/Test.sol";

// /// A place for Misc-like tests
// contract MiscTest is Test {
//     function testCallIndex() public {
//         assertEq(abi.encodePacked(uint8(uint256(108)), uint8(uint256(99))), hex"6c63");
//     }

//     function testAddressToBytes32Cast() public {
//         assertEq(
//             bytes32(bytes20(address(bytes20(hex"1231231231231231231231231231231231231231")))),
//             bytes32(hex"1231231231231231231231231231231231231231000000000000000000000000")
//         );

//         assertEq(
//             bytes32(abi.encodePacked(hex"1231231231231231231231231231231231231231")),
//             bytes32(
//                 abi.encodePacked(hex"1231231231231231231231231231231231231231", bytes(hex"000000000000000000000000"))
//             )
//         );
//     }

//     function testBytes32ToAddress() public {
//         assertEq(
//             address(bytes20(bytes32(hex"1231231231231231231231231231231231231231000000000000000000000000"))),
//             address(bytes20(hex"1231231231231231231231231231231231231231"))
//         );
//     }
// }
