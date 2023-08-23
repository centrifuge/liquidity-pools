// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.18;
pragma abicoder v2;

import {LiquidityPoolFactory, MemberlistFactory} from "src/liquidityPool/Factory.sol";
import {LiquidityPool} from "src/liquidityPool/LiquidityPool.sol";
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
        uint64 poolId,
        bytes16 trancheId,
        uint128 currency,
        address asset,
        address investmentManager,
        address admin,
        address memberlist,
        string memory name,
        string memory symbol,
        uint8 decimals
    ) public {
        vm.selectFork(mainnetFork);
        LiquidityPoolFactory lpFactory1 = new LiquidityPoolFactory{ salt: SALT }();
        address lp1 = lpFactory1.newLiquidityPool(
            poolId, trancheId, currency, asset, investmentManager, admin, memberlist, name, symbol, decimals
        );

        vm.selectFork(polygonFork);
        LiquidityPoolFactory lpFactory2 = new LiquidityPoolFactory{ salt: SALT }();
        assertEq(address(lpFactory1), address(lpFactory2));
        vm.prank(sender);
        address lp2 = lpFactory2.newLiquidityPool(
            poolId, trancheId, currency, asset, investmentManager, admin, memberlist, name, symbol, decimals
        );
        assertEq(address(lp1), address(lp2));
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
                            keccak256(abi.encodePacked(type(LiquidityPoolFactory).creationCode))
                        )
                    )
                )
            )
        );
        LiquidityPoolFactory lpFactory = new LiquidityPoolFactory{ salt: SALT }();
        assertEq(address(lpFactory), predictedAddress);
    }

    function testTrancheTokenShouldBeDeterministic(
        uint64 poolId,
        bytes16 trancheId,
        uint128 currency,
        address asset,
        address investmentManager,
        address admin,
        address memberlist,
        string memory name,
        string memory symbol,
        uint8 decimals
    ) public {
        LiquidityPoolFactory lpFactory = new LiquidityPoolFactory{ salt: SALT }();

        bytes32 salt = keccak256(abi.encodePacked(poolId, trancheId, currency));
        address predictedAddress = address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(
                            bytes1(0xff),
                            address(lpFactory),
                            salt,
                            keccak256(abi.encodePacked(type(LiquidityPool).creationCode, abi.encode(decimals)))
                        )
                    )
                )
            )
        );

        address token = lpFactory.newLiquidityPool(
            poolId, trancheId, currency, asset, investmentManager, admin, memberlist, name, symbol, decimals
        );

        assertEq(address(token), predictedAddress);
    }

    function testDeployingDeterministicAddressTwiceReverts(
        uint64 poolId,
        bytes16 trancheId,
        uint128 currency,
        address asset,
        address investmentManager,
        address admin,
        address memberlist,
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
                            keccak256(abi.encodePacked(type(LiquidityPoolFactory).creationCode))
                        )
                    )
                )
            )
        );
        LiquidityPoolFactory lpFactory = new LiquidityPoolFactory{ salt: SALT }();
        assertEq(address(lpFactory), predictedAddress);
        address lp1 = lpFactory.newLiquidityPool(
            poolId, trancheId, currency, asset, investmentManager, admin, memberlist, name, symbol, decimals
        );
        vm.expectRevert();
        address lp2 = lpFactory.newLiquidityPool(
            poolId, trancheId, currency, asset, investmentManager, admin, memberlist, name, symbol, decimals
        );
    }

    function testMemberlistFactoryIsDeterministicAcrossChains(address sender, address admin, address investmentManager)
        public
    {
        vm.selectFork(mainnetFork);
        MemberlistFactory memberlistFactory1 = new MemberlistFactory{ salt: SALT }();
        address memberlist1 = memberlistFactory1.newMemberlist(admin, investmentManager);

        vm.selectFork(polygonFork);
        MemberlistFactory memberlistFactory2 = new MemberlistFactory{ salt: SALT }();
        assertEq(address(memberlistFactory1), address(memberlistFactory2));
        vm.prank(sender);
        address memberlist2 = memberlistFactory2.newMemberlist(admin, investmentManager);
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
