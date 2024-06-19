// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import "forge-std/Test.sol";
import {AxelarRouter} from "src/gateway/routers/axelar/Router.sol";
import {MockAxelarGateway} from "test/mocks/MockAxelarGateway.sol";
import {MockGateway} from "test/mocks/MockGateway.sol";
import {MockAxelarGasService} from "test/mocks/MockAxelarGasService.sol";
import {AxelarForwarder} from "src/gateway/routers/axelar/Forwarder.sol";
import {BytesLib} from "src/libraries/BytesLib.sol";

contract AxelarRouterTest is Test {
    MockAxelarGateway axelarGateway;
    MockGateway gateway;
    MockAxelarGasService axelarGasService;
    AxelarRouter router;
    AxelarForwarder forwarder;

    string private constant axelarCentrifugeChainId = "centrifuge";
    string private constant axelarCentrifugeChainAddress = "0x7369626CEF070000000000000000000000000000";

    function setUp() public {
        axelarGateway = new MockAxelarGateway();
        gateway = new MockGateway();
        axelarGasService = new MockAxelarGasService();
        forwarder = new AxelarForwarder(address(axelarGateway));
        router = new AxelarRouter(address(gateway), address(axelarGateway), address(axelarGasService));
    }

    function testIncomingCalls(
        bytes32 commandId,
        string calldata sourceChain,
        string calldata sourceAddress,
        bytes calldata payload,
        address invalidOrigin,
        address relayer
    ) public {
        vm.assume(keccak256(abi.encodePacked(sourceChain)) != keccak256(abi.encodePacked("centrifuge")));
        vm.assume(invalidOrigin != address(axelarGateway));
        vm.assume(
            keccak256(abi.encodePacked(sourceAddress)) != keccak256(abi.encodePacked(axelarCentrifugeChainAddress))
        );
        vm.assume(relayer.code.length == 0);

        vm.prank(address(relayer));
        vm.expectRevert(bytes("AxelarRouter/invalid-source-chain"));
        router.execute(commandId, sourceChain, axelarCentrifugeChainAddress, payload);

        vm.prank(address(relayer));
        vm.expectRevert(bytes("AxelarRouter/invalid-source-address"));
        router.execute(commandId, axelarCentrifugeChainId, sourceAddress, payload);

        axelarGateway.setReturn("validateContractCall", false);
        vm.prank(address(relayer));
        vm.expectRevert(bytes("AxelarRouter/not-approved-by-axelar-gateway"));
        router.execute(commandId, axelarCentrifugeChainId, axelarCentrifugeChainAddress, payload);

        axelarGateway.setReturn("validateContractCall", true);
        vm.prank(address(relayer));
        router.execute(commandId, axelarCentrifugeChainId, axelarCentrifugeChainAddress, payload);
    }

    function testOutgoingCalls(bytes calldata message, address invalidOrigin) public {
        vm.assume(invalidOrigin != address(gateway));

        vm.expectRevert(bytes("AxelarRouter/only-gateway-allowed-to-call"));
        router.send(message);

        vm.prank(address(gateway));
        router.send(message);

        assertEq(axelarGateway.values_string("destinationChain"), axelarCentrifugeChainId);
        assertEq(axelarGateway.values_string("contractAddress"), router.CENTRIFUGE_AXELAR_EXECUTABLE());
        assertEq(axelarGateway.values_bytes("payload"), message);
    }
}
