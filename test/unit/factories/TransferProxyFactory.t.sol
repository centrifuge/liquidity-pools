// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import {TransferProxy, TransferProxyFactory} from "src/factories/TransferProxyFactory.sol";
import {ERC20} from "src/token/ERC20.sol";
import {MockPoolManager} from "test/mocks/MockPoolManager.sol";
import "forge-std/Test.sol";

contract TransferProxyFactoryTest is Test {
    MockPoolManager poolManager;
    TransferProxyFactory factory;
    ERC20 erc20;

    function setUp() public {
        poolManager = new MockPoolManager();
        factory = new TransferProxyFactory(address(poolManager));
        erc20 = new ERC20(18);
    }

    function testTransferProxy(bytes32 destination, bytes32 otherDestination) public {
        vm.assume(destination != otherDestination);

        TransferProxy proxy = TransferProxy(factory.newTransferProxy(destination));
        assertEq(factory.poolManager(), address(poolManager));
        assertEq(factory.proxies(destination), address(proxy));
        assertEq(address(proxy.poolManager()), address(poolManager));
        assertEq(proxy.destination(), destination);

        // Proxies cannot be deployed twice
        vm.expectRevert(bytes("TransferProxyFactory/proxy-already-deployed"));
        factory.newTransferProxy(destination);

        erc20.mint(address(this), 100);
        erc20.transfer(address(proxy), 100);

        assertEq(poolManager.values_address("currency"), address(0));
        assertEq(poolManager.values_bytes32("recipient"), "");
        assertEq(poolManager.values_uint128("amount"), 0);

        // Transfers are processed as expected
        proxy.transfer(address(erc20), 100);
        assertEq(poolManager.values_address("currency"), address(erc20));
        assertEq(poolManager.values_bytes32("recipient"), destination);
        assertEq(poolManager.values_uint128("amount"), 100);

        // Proxies are unique per destination
        assertTrue(factory.newTransferProxy(otherDestination) != address(proxy));
    }
}
