// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import {AxelarRouter} from "src/gateway/routers/axelar/Router.sol";
import {AxelarGatewayMock} from "../../../mock/AxelarGatewayMock.sol";
import {GatewayMock} from "../../../mock/GatewayMock.sol";
import "forge-std/Test.sol";
import {AxelarForwarder} from "../../../../src/gateway/routers/axelar/Forwarder.sol";
import {BytesLib} from "../../../../src/util/BytesLib.sol";

contract AxelarRouterTest is Test {
    AxelarGatewayMock axelarGateway;
    GatewayMock gateway;
    AxelarRouter router;
    AxelarForwarder forwarder;

    string private constant axelarCentrifugeChainId = "centrifuge";
    string private constant axelarCentrifugeChainAddress = "0x7369626CEF070000000000000000000000000000";

    function setUp() public {
        axelarGateway = new AxelarGatewayMock();
        gateway = new GatewayMock();

        forwarder = new AxelarForwarder(address(axelarGateway));
        router = new AxelarRouter(address(axelarGateway), AxelarRouterTest.toHex(abi.encodePacked(forwarder)));
        router.file("gateway", address(gateway));
    }

    function testInvalidFile() public {
        vm.expectRevert("AxelarRouter/file-unrecognized-param");
        router.file("not-gateway", address(1));
    }

    function testFileGateway(address invalidOrigin, address anotherGateway) public {
        vm.assume(invalidOrigin != address(this));

        vm.prank(invalidOrigin);
        vm.expectRevert(bytes("Auth/not-authorized"));
        router.file("gateway", anotherGateway);

        router.file("gateway", anotherGateway);
        assertEq(address(router.gateway()), anotherGateway);
    }

    function testFileExecutable(address invalidOrigin, string memory anotherExecutable) public {
        vm.assume(invalidOrigin != address(this));

        vm.prank(invalidOrigin);
        vm.expectRevert(bytes("Auth/not-authorized"));
        router.file("executable", anotherExecutable);

        router.file("executable", anotherExecutable);
        assertEq(router.centrifugeAxelarExecutable(), anotherExecutable);
    }

    function testIncomingCalls(
        bytes32 commandId,
        string calldata sourceChain,
        string calldata sourceAddress,
        bytes calldata payload,
        address invalidOrigin,
        string memory invalidAxelarCentrifugeChainId,
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
        vm.expectRevert(bytes("Router/not-approved-by-gateway"));
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
        assertEq(axelarGateway.values_string("contractAddress"), AxelarRouterTest.toHex(abi.encodePacked(forwarder)));
        assertEq(axelarGateway.values_bytes("payload"), message);
    }

    function toHex(bytes memory _bytes) public pure returns (string memory) {
        // Fixed buffer size for hexadecimal convertion
        bytes memory converted = new bytes(_bytes.length * 2);

        bytes memory _base = "0123456789abcdef";

        for (uint256 i = 0; i < _bytes.length; i++) {
            converted[i * 2] = _base[uint8(_bytes[i]) / _base.length];
            converted[i * 2 + 1] = _base[uint8(_bytes[i]) % _base.length];
        }

        return string(abi.encodePacked("0x", converted));
    }
}
