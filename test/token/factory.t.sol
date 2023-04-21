// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.18;
pragma abicoder v2;

import {TrancheTokenFactory, MemberlistFactory} from "src/token/factory.sol";
import {RestrictedToken} from "src/token/restricted.sol";
import "forge-std/Test.sol";

contract FactoryTest is Test {
    // address(0)[0:20] + keccak("Centrifuge")[21:32]
    bytes32 SALT = 0x000000000000000000000000000000000000000075eb27011b69f002dc094d05;

    function setUp() public {}

    function testTokenFactoryAddressIsDeterministicAcrossChains(
        address sender,
        string memory name,
        string memory symbol,
        uint64 poolId,
        bytes16 trancheId,
        uint8 decimals
    ) public {
        uint256 mainnetFork = vm.createFork(vm.envString("MAINNET_RPC_URL"));
        uint256 polygonFork = vm.createFork(vm.envString("POLYGON_RPC_URL"));
        vm.selectFork(mainnetFork);
        TrancheTokenFactory tokenFactory1 = new TrancheTokenFactory{ salt: SALT }();
        address token1 = tokenFactory1.newTrancheToken(poolId, trancheId, name, symbol, decimals);

        vm.selectFork(polygonFork);
        TrancheTokenFactory tokenFactory2 = new TrancheTokenFactory{ salt: SALT }();
        assertEq(address(tokenFactory1), address(tokenFactory2));
        vm.prank(sender);
        address token2 = tokenFactory2.newTrancheToken(poolId, trancheId, name, symbol, decimals);
        assertEq(address(token1), address(token2));
    }

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

    function testDeployingDeterministicAddressTwiceReverts() public {
        address predictedAddress = address(uint160(uint(keccak256(abi.encodePacked(
            bytes1(0xff),
            address(this),
            SALT,
            keccak256(abi.encodePacked(
                type(TrancheTokenFactory).creationCode
            ))
        )))));
        TrancheTokenFactory tokenFactory1 = new TrancheTokenFactory{ salt: SALT }();
        assertEq(address(tokenFactory1), predictedAddress);
        vm.expectRevert();
        TrancheTokenFactory tokenFactory2 = new TrancheTokenFactory{ salt: SALT }();
    }
}
