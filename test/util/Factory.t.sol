// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import {TrancheTokenFactory} from "src/util/Factory.sol";
import {TrancheToken} from "src/token/Tranche.sol";
import {Root} from "src/Root.sol";
import {Escrow} from "src/Escrow.sol";
import {TestSetup} from "test/TestSetup.t.sol";
import "forge-std/Test.sol";

interface PoolManagerLike {
    function getTrancheToken(uint64 poolId, bytes16 trancheId) external view returns (address);
}

contract FactoryTest is Test {
    uint256 mainnetFork;
    uint256 polygonFork;

    address root;

    function setUp() public {
        mainnetFork = vm.createFork(vm.envString("MAINNET_RPC_URL"));
        polygonFork = vm.createFork(vm.envString("POLYGON_RPC_URL"));

        root = address(new Root(address(new Escrow(address(this))), 48 hours, address(this)));
    }

    function testTrancheTokenFactoryIsDeterministicAcrossChains(
        uint64 poolId,
        bytes16 trancheId,
        address investmentManager1,
        address investmentManager2,
        address poolManager1,
        address poolManager2
    ) public {
        bytes32 salt = keccak256(abi.encodePacked("test"));

        vm.selectFork(mainnetFork);
        TestSetup testSetup1 = new TestSetup{salt: salt}();
        testSetup1.setUp();
        testSetup1.deployLiquidityPool(poolId, 18, "", "", trancheId, 1, address(testSetup1.erc20()));
        address trancheToken1 = PoolManagerLike(address(testSetup1.poolManager())).getTrancheToken(poolId, trancheId);
        address root1 = address(testSetup1.root());

        vm.selectFork(polygonFork);
        TestSetup testSetup2 = new TestSetup{salt: salt}();
        testSetup2.setUp();
        testSetup2.deployLiquidityPool(poolId, 18, "", "", trancheId, 1, address(testSetup2.erc20()));
        address trancheToken2 = PoolManagerLike(address(testSetup2.poolManager())).getTrancheToken(poolId, trancheId);
        address root2 = address(testSetup2.root());

        assertEq(address(root1), address(root2));
        assertEq(trancheToken1, trancheToken2);
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
                            keccak256(
                                abi.encodePacked(
                                    type(TrancheTokenFactory).creationCode, abi.encode(root), abi.encode(address(this))
                                )
                            )
                        )
                    )
                )
            )
        );
        TrancheTokenFactory trancheTokenFactory = new TrancheTokenFactory{ salt: salt }(root, address(this));
        assertEq(address(trancheTokenFactory), predictedAddress);
    }

    function testTrancheTokenShouldBeDeterministic(
        bytes32 salt,
        uint64 poolId,
        bytes16 trancheId,
        address investmentManager,
        address poolManager,
        address restrictionManager,
        string memory name,
        string memory symbol,
        uint8 decimals
    ) public {
        TrancheTokenFactory trancheTokenFactory = new TrancheTokenFactory{ salt: salt }(root, address(this));

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

        address token = trancheTokenFactory.newTrancheToken(
            poolId, trancheId, name, symbol, decimals, restrictionManager, trancheTokenWards
        );

        assertEq(address(token), predictedAddress);
    }

    function testDeployingDeterministicAddressTwiceReverts(
        bytes32 salt,
        uint64 poolId,
        bytes16 trancheId,
        address investmentManager,
        address poolManager,
        address restrictionManager,
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
                            keccak256(
                                abi.encodePacked(
                                    type(TrancheTokenFactory).creationCode, abi.encode(root), abi.encode(address(this))
                                )
                            )
                        )
                    )
                )
            )
        );

        address[] memory trancheTokenWards = new address[](2);
        trancheTokenWards[0] = address(investmentManager);
        trancheTokenWards[1] = address(poolManager);

        TrancheTokenFactory trancheTokenFactory = new TrancheTokenFactory{ salt: salt }(root, address(this));
        assertEq(address(trancheTokenFactory), predictedAddress);
        address token1 = trancheTokenFactory.newTrancheToken(
            poolId, trancheId, name, symbol, decimals, restrictionManager, trancheTokenWards
        );
        vm.expectRevert();
        address token2 = trancheTokenFactory.newTrancheToken(
            poolId, trancheId, name, symbol, decimals, restrictionManager, trancheTokenWards
        );
        // assertEq(token1, token2);
    }
}
