// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import {TrancheTokenFactory} from "src/util/Factory.sol";
import {TrancheToken} from "src/token/Tranche.sol";
import {Root} from "src/Root.sol";
import {Escrow} from "src/Escrow.sol";
import "forge-std/Test.sol";

contract FactoryTest is Test {
    address root;

    function setUp() public {
        root = address(new Root(address(new Escrow()), 48 hours));
    }

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

        bytes32 hashedSalt = keccak256(abi.encodePacked(poolId, trancheId));
        address predictedAddress = address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(
                            bytes1(0xff),
                            address(trancheTokenFactory),
                            hashedSalt,
                            keccak256(abi.encodePacked(type(TrancheToken).creationCode, abi.encode(decimals)))
                        )
                    )
                )
            )
        );

        address[] memory trancheTokenWards = new address[](2);
        trancheTokenWards[0] = address(investmentManager);
        trancheTokenWards[1] = address(poolManager);

        address token =
            trancheTokenFactory.newTrancheToken(poolId, trancheId, name, symbol, decimals, trancheTokenWards);

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

        TrancheTokenFactory trancheTokenFactory = new TrancheTokenFactory{ salt: salt }(root);
        assertEq(address(trancheTokenFactory), predictedAddress);
        trancheTokenFactory.newTrancheToken(poolId, trancheId, name, symbol, decimals, trancheTokenWards);
        vm.expectRevert();
        trancheTokenFactory.newTrancheToken(poolId, trancheId, name, symbol, decimals, trancheTokenWards);
    }
}
