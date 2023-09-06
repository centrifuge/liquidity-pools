// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import {TrancheTokenFactory} from "src/util/Factory.sol";
import {TrancheToken} from "src/token/Tranche.sol";
import {Root} from "src/Root.sol";
import {Escrow} from "src/Escrow.sol";
import "forge-std/Test.sol";

contract FactoryTest is Test {
    uint256 mainnetFork;
    uint256 polygonFork;

    address root;

    function setUp() public {
        root = address(new Root(address(new Escrow()), 48 hours));
    }

    // TODO: re-enable this
    // function testTrancheTokenFactoryIsDeterministicAcrossChains(
    //     bytes32 salt,
    //     address sender,
    //     uint64 poolId,
    //     bytes16 trancheId,
    //     address investmentManager1,
    //     address investmentManager2,
    //     address poolManager1,
    //     address poolManager2,
    //     string memory name,
    //     string memory symbol,
    //     uint8 decimals
    // ) public {
    //     vm.assume(sender != address(0));
    //     mainnetFork = vm.createFork(vm.envString("MAINNET_RPC_URL"));
    //     polygonFork = vm.createFork(vm.envString("POLYGON_RPC_URL"));

    //     vm.selectFork(mainnetFork);
    //     TrancheTokenFactory trancheTokenFactory1 = new TrancheTokenFactory{ salt: salt }(root);
    //     address trancheToken1 = trancheTokenFactory1.newTrancheToken(
    //         poolId, trancheId, investmentManager1, poolManager1, name, symbol, decimals
    //     );

    //     vm.selectFork(polygonFork);
    //     vm.prank(sender);
    //     TrancheTokenFactory trancheTokenFactory2 = new TrancheTokenFactory{ salt: salt }(root);
    //     assertEq(address(trancheTokenFactory1), address(trancheTokenFactory2));
    //     address trancheToken2 = trancheTokenFactory2.newTrancheToken(
    //         poolId, trancheId, investmentManager2, poolManager2, name, symbol, decimals
    //     );
    //     assertEq(address(trancheToken1), address(trancheToken2));
    // }

    function testTrancheTokenFactoryShouldBeDeterministic(bytes32 salt) public {
        address predictedAddress = address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(
                            bytes1(0xff),
                            address(this),
                            salt,
                            keccak256(abi.encodePacked(type(TrancheTokenFactory).creationCode, abi.encode(root)))
                        )
                    )
                )
            )
        );
        TrancheTokenFactory trancheTokenFactory = new TrancheTokenFactory{ salt: salt }(root);
        assertEq(address(trancheTokenFactory), predictedAddress);
    }

    function testTrancheTokenShouldBeDeterministic(
        bytes32 salt,
        uint64 poolId,
        bytes16 trancheId,
        address investmentManager,
        address poolManager,
        string memory name,
        string memory symbol,
        uint8 decimals
    ) public {
        TrancheTokenFactory trancheTokenFactory = new TrancheTokenFactory{ salt: salt }(root);

        bytes32 salt = keccak256(abi.encodePacked(poolId, trancheId));
        address predictedAddress = address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(
                            bytes1(0xff),
                            address(trancheTokenFactory),
                            salt,
                            keccak256(abi.encodePacked(type(TrancheToken).creationCode, abi.encode(decimals)))
                        )
                    )
                )
            )
        );

        address[] memory trancheTokenWards = new address[](2);
        trancheTokenWards[0] = address(investmentManager);
        trancheTokenWards[1] = address(poolManager);

        address[] memory memberlistWards = new address[](1);
        memberlistWards[0] = address(poolManager);

        address token = trancheTokenFactory.newTrancheToken(
            poolId, trancheId, name, symbol, decimals, trancheTokenWards, memberlistWards
        );

        assertEq(address(token), predictedAddress);
    }

    function testDeployingDeterministicAddressTwiceReverts(
        bytes32 salt,
        uint64 poolId,
        bytes16 trancheId,
        address investmentManager,
        address poolManager,
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
                            salt,
                            keccak256(abi.encodePacked(type(TrancheTokenFactory).creationCode, abi.encode(root)))
                        )
                    )
                )
            )
        );

        address[] memory trancheTokenWards = new address[](2);
        trancheTokenWards[0] = address(investmentManager);
        trancheTokenWards[1] = address(poolManager);

        address[] memory memberlistWards = new address[](1);
        memberlistWards[0] = address(poolManager);

        TrancheTokenFactory trancheTokenFactory = new TrancheTokenFactory{ salt: salt }(root);
        assertEq(address(trancheTokenFactory), predictedAddress);
        trancheTokenFactory.newTrancheToken(
            poolId, trancheId, name, symbol, decimals, trancheTokenWards, memberlistWards
        );
        vm.expectRevert();
        trancheTokenFactory.newTrancheToken(
            poolId, trancheId, name, symbol, decimals, trancheTokenWards, memberlistWards
        );
    }
}
