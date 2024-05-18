// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import {TrancheTokenFactory} from "src/factories/TrancheTokenFactory.sol";
import {TrancheToken01} from "src/token/TrancheToken01.sol";
import {Root} from "src/Root.sol";
import {Escrow} from "src/Escrow.sol";
import {BaseTest} from "test/BaseTest.sol";
import "forge-std/Test.sol";

interface PoolManagerLike {
    function getTrancheToken(uint64 poolId, bytes16 trancheId) external view returns (address);
}

contract FactoryTest is Test {
    uint256 mainnetFork;
    uint256 polygonFork;
    address root;
    address escrow;

    function setUp() public {
        if (vm.envOr("FORK_TESTS", false)) {
            mainnetFork = vm.createFork(vm.rpcUrl("ethereum-mainnet"));
            polygonFork = vm.createFork(vm.rpcUrl("polygon-mainnet"));
        }

        escrow = address(new Escrow(address(this)));
        root = address(new Root(escrow, 48 hours, address(this)));
    }

    function testTrancheTokenFactoryIsDeterministicAcrossChains(uint64 poolId, bytes16 trancheId) public {
        if (vm.envOr("FORK_TESTS", false)) {
            vm.setEnv("DEPLOYMENT_SALT", "0x290decd9548b62a8d60345a988386fc84ba6bc95484008f6362f93160ef3e563");
            vm.selectFork(mainnetFork);
            BaseTest testSetup1 = new BaseTest{salt: keccak256(abi.encode(vm.envString("DEPLOYMENT_SALT")))}();
            testSetup1.setUp();
            testSetup1.deployVault(
                poolId, 18, testSetup1.defaultTrancheType(), "", "", trancheId, 1, address(testSetup1.erc20())
            );
            address trancheToken1 =
                PoolManagerLike(address(testSetup1.poolManager())).getTrancheToken(poolId, trancheId);
            address root1 = address(testSetup1.root());

            vm.selectFork(polygonFork);
            BaseTest testSetup2 = new BaseTest{salt: keccak256(abi.encode(vm.envString("DEPLOYMENT_SALT")))}();
            testSetup2.setUp();
            testSetup2.deployVault(
                poolId, 18, testSetup2.defaultTrancheType(), "", "", trancheId, 1, address(testSetup2.erc20())
            );
            address trancheToken2 =
                PoolManagerLike(address(testSetup2.poolManager())).getTrancheToken(poolId, trancheId);
            address root2 = address(testSetup2.root());

            assertEq(address(root1), address(root2));
            assertEq(trancheToken1, trancheToken2);
        }
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
        TrancheTokenFactory trancheTokenFactory = new TrancheTokenFactory{salt: salt}(root, address(this));
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
        uint8 decimals,
        uint8 trancheType
    ) public {
        decimals = uint8(bound(decimals, 1, 18));

        TrancheTokenFactory trancheTokenFactory = new TrancheTokenFactory{salt: salt}(root, address(this));

        bytes32 hashedSalt = keccak256(abi.encodePacked(poolId, trancheId));
        address predictedAddress = address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(
                            bytes1(0xff),
                            address(trancheTokenFactory),
                            hashedSalt,
                            keccak256(
                                abi.encodePacked(
                                    type(TrancheToken01).creationCode, abi.encode(decimals), abi.encode(escrow)
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

        address token = trancheTokenFactory.newTrancheToken(
            poolId, trancheId, name, symbol, decimals, trancheTokenWards, trancheType
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
        uint8 decimals,
        uint8 trancheType
    ) public {
        decimals = uint8(bound(decimals, 1, 18));

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

        TrancheTokenFactory trancheTokenFactory = new TrancheTokenFactory{salt: salt}(root, address(this));
        assertEq(address(trancheTokenFactory), predictedAddress);

        trancheTokenFactory.newTrancheToken(poolId, trancheId, name, symbol, decimals, trancheTokenWards, trancheType);
        vm.expectRevert();
        trancheTokenFactory.newTrancheToken(poolId, trancheId, name, symbol, decimals, trancheTokenWards, trancheType);
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
