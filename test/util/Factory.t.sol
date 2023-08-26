// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.18;
pragma abicoder v2;

import {LiquidityPoolFactory} from "src/util/Factory.sol";
import {LiquidityPool} from "src/LiquidityPool.sol";
import {Root} from "src/Root.sol";
import {Escrow} from "src/Escrow.sol";
import "forge-std/Test.sol";

contract FactoryTest is Test {
    uint256 mainnetFork;
    uint256 polygonFork;

    address root;

    function setUp() public {
        mainnetFork = vm.createFork(vm.envString("MAINNET_RPC_URL"));
        polygonFork = vm.createFork(vm.envString("POLYGON_RPC_URL"));

        root = address(new Root(address(new Escrow()), 48 hours));
    }

    function testTokenFactoryIsDeterministicAcrossChains(
        bytes32 salt,
        address sender,
        uint64 poolId,
        bytes16 trancheId,
        address token,
        uint128 currency,
        address asset,
        address investmentManager,
        address admin
    ) public {
        vm.assume(sender != address(0));

        vm.selectFork(mainnetFork);
        LiquidityPoolFactory lpFactory1 = new LiquidityPoolFactory{ salt: salt }(root);
        address lp1 = lpFactory1.newLiquidityPool(poolId, trancheId, currency, asset, token, investmentManager);

        vm.selectFork(polygonFork);
        LiquidityPoolFactory lpFactory2 = new LiquidityPoolFactory{ salt: salt }(root);
        assertEq(address(lpFactory1), address(lpFactory2));
        vm.prank(sender);
        address lp2 = lpFactory2.newLiquidityPool(poolId, trancheId, currency, asset, token, investmentManager);
        assertEq(address(lp1), address(lp2));
    }

    function testTokenFactoryShouldBeDeterministic(bytes32 salt) public {
        address predictedAddress = address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(
                            bytes1(0xff),
                            address(this),
                            salt,
                            keccak256(abi.encodePacked(type(LiquidityPoolFactory).creationCode, abi.encode(root)))
                        )
                    )
                )
            )
        );
        LiquidityPoolFactory lpFactory = new LiquidityPoolFactory{ salt: salt }(root);
        assertEq(address(lpFactory), predictedAddress);
    }

    function testLiquidityPoolShouldBeDeterministic(
        bytes32 salt,
        uint64 poolId,
        bytes16 trancheId,
        uint128 currency,
        address asset,
        address token,
        address investmentManager,
        address admin
    ) public {
        LiquidityPoolFactory lpFactory = new LiquidityPoolFactory{ salt: salt }(root);

        bytes32 salt = keccak256(abi.encodePacked(poolId, trancheId, currency));
        address predictedAddress = address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(
                            bytes1(0xff),
                            address(lpFactory),
                            salt,
                            keccak256(abi.encodePacked(type(LiquidityPool).creationCode))
                        )
                    )
                )
            )
        );

        address token = lpFactory.newLiquidityPool(poolId, trancheId, currency, asset, token, investmentManager);

        assertEq(address(token), predictedAddress);
    }

    function testDeployingDeterministicAddressTwiceReverts(
        bytes32 salt,
        uint64 poolId,
        bytes16 trancheId,
        uint128 currency,
        address asset,
        address token,
        address investmentManager,
        address admin
    ) public {
        address predictedAddress = address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(
                            bytes1(0xff),
                            address(this),
                            salt,
                            keccak256(abi.encodePacked(type(LiquidityPoolFactory).creationCode, abi.encode(root)))
                        )
                    )
                )
            )
        );
        LiquidityPoolFactory lpFactory = new LiquidityPoolFactory{ salt: salt }(root);
        assertEq(address(lpFactory), predictedAddress);
        address lp1 = lpFactory.newLiquidityPool(poolId, trancheId, currency, asset, token, investmentManager);
        vm.expectRevert();
        address lp2 = lpFactory.newLiquidityPool(poolId, trancheId, currency, asset, token, investmentManager);
    }
}
