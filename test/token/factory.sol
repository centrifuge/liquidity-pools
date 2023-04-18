// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.18;
pragma abicoder v2;

import {TrancheTokenFactory, MemberlistFactory} from "src/token/factory.sol";
import {RestrictedToken} from "src/token/restricted.sol";
import "forge-std/Test.sol";

contract FactoryTest is Test {
    // address(0)[0:20] + keccak("Centrifuge")[21:32]
    bytes32 SALT = 0x000000000000000000000000000000000000000075eb27011b69f002dc094d05;

    bool isFirstRun = false;
    address tokenFactoryAddress;
    address tokenAddress;

    function setUp() public {}

    // function testTokenAddressShouldBeDeterministic1(
    //     address sender,
    //     uint64 chainId,
    //     string memory name,
    //     string memory symbol
    // ) public {
    //     TrancheTokenFactory tokenFactory = new TrancheTokenFactory{ salt: SALT }();

    //     if (isFirstRun) {
    //         tokenFactoryAddress = address(tokenFactory);
    //     } else {
    //         assertEq(address(tokenFactory), tokenFactoryAddress);
    //     }

    //     vm.prank(sender);
    //     vm.chainId(uint256(chainId));

    //     uint64 fixedPoolId = 1;
    //     bytes16 fixedTrancheId = "1";
    //     uint8 fixedDecimals = 18;

    //     address token = tokenFactory.newTrancheToken(fixedPoolId, fixedTrancheId, name, symbol, fixedDecimals);

    //     if (isFirstRun) {
    //         tokenAddress = address(tokenFactory);
    //         isFirstRun = false;
    //     } else {
    //         assertEq(token, tokenAddress);
    //     }
    // }

    function testTokenFactoryAddressShouldBeDeterministic() public {
        address predictedAddress = address(uint160(uint(keccak256(abi.encodePacked(
            bytes1(0xff),
            address(this),
            SALT,
            keccak256(abi.encodePacked(
                type(TrancheTokenFactory).creationCode
            ))
        )))));
        TrancheTokenFactory tokenFactory = new TrancheTokenFactory{ salt: SALT }();
        assertEq(address(tokenFactory), predictedAddress);
    }

    function testTrancheTokenAddressShouldBeDeterministic(uint64 poolId, bytes16 trancheId, string memory name, string memory symbol, uint8 decimals) public {
        TrancheTokenFactory tokenFactory = new TrancheTokenFactory{ salt: SALT }();

        bytes32 salt = keccak256(abi.encodePacked(poolId, trancheId));
        address predictedAddress = address(uint160(uint(keccak256(abi.encodePacked(
            bytes1(0xff),
            address(tokenFactory),
            salt,
            keccak256(abi.encodePacked(
                type(RestrictedToken).creationCode,
                abi.encode(decimals)
            ))
        )))));

        address token = tokenFactory.newTrancheToken(poolId, trancheId, name, symbol, decimals);

        assertEq(address(token), predictedAddress);
    }

    function testDeployingDeterministicAddressTwice() public {
        address predictedAddress = address(uint160(uint(keccak256(abi.encodePacked(
            bytes1(0xff),
            address(this),
            SALT,
            keccak256(abi.encodePacked(
                type(TrancheTokenFactory).creationCode
            ))
        )))));
        TrancheTokenFactory tokenFactory1 = new TrancheTokenFactory{ salt: SALT }();
        TrancheTokenFactory tokenFactory2 = new TrancheTokenFactory{ salt: SALT }();
        assertEq(address(tokenFactory1), predictedAddress);
        assertEq(address(tokenFactory2), predictedAddress);
    }
}
