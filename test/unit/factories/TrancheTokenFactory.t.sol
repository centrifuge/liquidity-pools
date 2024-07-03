// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.26;

import {TrancheFactory} from "src/factories/TrancheFactory.sol";
import {Tranche} from "src/token/Tranche.sol";
import {Root} from "src/Root.sol";
import {Escrow} from "src/Escrow.sol";
import {BaseTest} from "test/BaseTest.sol";
import "forge-std/Test.sol";

interface PoolManagerLike {
    function getTranche(uint64 poolId, bytes16 trancheId) external view returns (address);
}

contract FactoryTest is Test {
    uint256 mainnetFork;
    uint256 polygonFork;
    address root;

    function setUp() public {
        if (vm.envOr("FORK_TESTS", false)) {
            mainnetFork = vm.createFork(vm.rpcUrl("ethereum-mainnet"));
            polygonFork = vm.createFork(vm.rpcUrl("polygon-mainnet"));
        }

        root = address(new Root(address(new Escrow(address(this))), 48 hours, address(this)));
    }

    function testTrancheFactoryIsDeterministicAcrossChains(uint64 poolId, bytes16 trancheId) public {
        if (vm.envOr("FORK_TESTS", false)) {
            vm.setEnv("DEPLOYMENT_SALT", "0x290decd9548b62a8d60345a988386fc84ba6bc95484008f6362f93160ef3e563");
            vm.selectFork(mainnetFork);
            BaseTest testSetup1 = new BaseTest{salt: keccak256(abi.encode(vm.envString("DEPLOYMENT_SALT")))}();
            testSetup1.setUp();
            testSetup1.deployVault(
                poolId, 18, testSetup1.restrictionManager(), "", "", trancheId, 1, address(testSetup1.erc20())
            );
            address tranche1 = PoolManagerLike(address(testSetup1.poolManager())).getTranche(poolId, trancheId);
            address root1 = address(testSetup1.root());

            vm.selectFork(polygonFork);
            BaseTest testSetup2 = new BaseTest{salt: keccak256(abi.encode(vm.envString("DEPLOYMENT_SALT")))}();
            testSetup2.setUp();
            testSetup2.deployVault(
                poolId, 18, testSetup2.restrictionManager(), "", "", trancheId, 1, address(testSetup2.erc20())
            );
            address tranche2 = PoolManagerLike(address(testSetup2.poolManager())).getTranche(poolId, trancheId);
            address root2 = address(testSetup2.root());

            assertEq(address(root1), address(root2));
            assertEq(tranche1, tranche2);
        }
    }

    function testTrancheFactoryShouldBeDeterministic(bytes32 salt) public {
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
                                    type(TrancheFactory).creationCode, abi.encode(root), abi.encode(address(this))
                                )
                            )
                        )
                    )
                )
            )
        );
        TrancheFactory trancheFactory = new TrancheFactory{salt: salt}(root, address(this));
        assertEq(address(trancheFactory), predictedAddress);
    }

    function testTrancheShouldBeDeterministic(
        bytes32 salt,
        uint64 poolId,
        bytes16 trancheId,
        address investmentManager,
        address poolManager,
        string memory name,
        string memory symbol,
        uint8 decimals
    ) public {
        decimals = uint8(bound(decimals, 0, 18));
        TrancheFactory trancheFactory = new TrancheFactory{salt: salt}(root, address(this));

        bytes32 hashedSalt = keccak256(abi.encodePacked(poolId, trancheId));
        address predictedAddress = address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(
                            bytes1(0xff),
                            address(trancheFactory),
                            hashedSalt,
                            keccak256(abi.encodePacked(type(Tranche).creationCode, abi.encode(decimals)))
                        )
                    )
                )
            )
        );

        address[] memory trancheWards = new address[](2);
        trancheWards[0] = address(investmentManager);
        trancheWards[1] = address(poolManager);

        address token = trancheFactory.newTranche(poolId, trancheId, name, symbol, decimals, trancheWards);

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
        decimals = uint8(bound(decimals, 0, 18));
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
                                    type(TrancheFactory).creationCode, abi.encode(root), abi.encode(address(this))
                                )
                            )
                        )
                    )
                )
            )
        );

        address[] memory trancheWards = new address[](2);
        trancheWards[0] = address(investmentManager);
        trancheWards[1] = address(poolManager);

        TrancheFactory trancheFactory = new TrancheFactory{salt: salt}(root, address(this));
        assertEq(address(trancheFactory), predictedAddress);

        trancheFactory.newTranche(poolId, trancheId, name, symbol, decimals, trancheWards);
        vm.expectRevert();
        trancheFactory.newTranche(poolId, trancheId, name, symbol, decimals, trancheWards);
    }

    function _stringToBytes32(string memory source) internal pure returns (bytes32 result) {
        bytes memory tempEmptyStringTest = bytes(source);
        if (tempEmptyStringTest.length == 0) {
            return 0x0;
        }

        assembly {
            result := mload(add(source, 32))
        }
    }
}
