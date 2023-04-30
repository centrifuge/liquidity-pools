// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.18;
pragma abicoder v2;

import {TrancheTokenFactory, MemberlistFactory} from "src/token/factory.sol";
import {RestrictedToken} from "src/token/restricted.sol";
import "forge-std/Test.sol";

contract FactoryTest is Test {
    // address(0)[0:20] + keccak("Centrifuge")[21:32]
    bytes32 SALT = 0x000000000000000000000000000000000000000075eb27011b69f002dc094d05;
    uint256 mainnetFork;
    uint256 polygonFork;

    function setUp() public {
        mainnetFork = vm.createFork(vm.envString("MAINNET_RPC_URL"));
        polygonFork = vm.createFork(vm.envString("POLYGON_RPC_URL"));
    }

    function testTokenFactoryIsDeterministicAcrossChains(
        address sender,
        string memory name,
        string memory symbol,
        uint64 poolId,
        bytes16 trancheId,
        uint8 decimals
    ) public {
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

    function testTokenFactoryShouldBeDeterministic() public {
        address predictedAddress = address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(
                            bytes1(0xff),
                            address(this),
                            SALT,
                            keccak256(abi.encodePacked(type(TrancheTokenFactory).creationCode))
                        )
                    )
                )
            )
        );
        TrancheTokenFactory tokenFactory = new TrancheTokenFactory{ salt: SALT }();
        assertEq(address(tokenFactory), predictedAddress);
    }

    function testTrancheTokenShouldBeDeterministic(
        uint64 poolId,
        bytes16 trancheId,
        string memory name,
        string memory symbol,
        uint8 decimals
    ) public {
        TrancheTokenFactory tokenFactory = new TrancheTokenFactory{ salt: SALT }();

        bytes32 salt = keccak256(abi.encodePacked(poolId, trancheId));
        address predictedAddress = address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(
                            bytes1(0xff),
                            address(tokenFactory),
                            salt,
                            keccak256(abi.encodePacked(type(RestrictedToken).creationCode, abi.encode(decimals)))
                        )
                    )
                )
            )
        );

        address token = tokenFactory.newTrancheToken(poolId, trancheId, name, symbol, decimals);

        assertEq(address(token), predictedAddress);
    }

    function testDeployingDeterministicAddressTwiceReverts(
        uint64 poolId,
        bytes16 trancheId,
        string memory name,
        string memory symbol,
        uint8 decimals
    ) public {
        address predictedAddress = address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(
                            bytes1(0xff),
                            address(this),
                            SALT,
                            keccak256(abi.encodePacked(type(TrancheTokenFactory).creationCode))
                        )
                    )
                )
            )
        );
        TrancheTokenFactory tokenFactory = new TrancheTokenFactory{ salt: SALT }();
        assertEq(address(tokenFactory), predictedAddress);
        address token1 = tokenFactory.newTrancheToken(poolId, trancheId, name, symbol, decimals);
        vm.expectRevert();
        address token2 = tokenFactory.newTrancheToken(poolId, trancheId, name, symbol, decimals);
    }

    function testMemberlistFactoryIsDeterministicAcrossChains(
        address sender,
        uint64 poolId,
        bytes16 trancheId,
        uint256 threshold
    ) public {
        vm.selectFork(mainnetFork);
        MemberlistFactory memberlistFactory1 = new MemberlistFactory{ salt: SALT }();
        address memberlist1 = memberlistFactory1.newMemberlist();

        vm.selectFork(polygonFork);
        MemberlistFactory memberlistFactory2 = new MemberlistFactory{ salt: SALT }();
        assertEq(address(memberlistFactory1), address(memberlistFactory2));
        vm.prank(sender);
        address memberlist2 = memberlistFactory2.newMemberlist();
        assertEq(address(memberlist1), address(memberlist2));
    }

    function testMemberlistShouldBeDeterministic() public {
        address predictedAddress = address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(
                            bytes1(0xff),
                            address(this),
                            SALT,
                            keccak256(abi.encodePacked(type(MemberlistFactory).creationCode))
                        )
                    )
                )
            )
        );
        MemberlistFactory memberlistFactory = new MemberlistFactory{ salt: SALT }();
        assertEq(address(memberlistFactory), predictedAddress);
    }
}
