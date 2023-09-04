// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import {AxelarEVMRouter} from "src/gateway/routers/axelar/EVMRouter.sol";
import {AxelarGatewayMock} from "../../../mock/AxelarGatewayMock.sol";
import {GatewayMock} from "../../../mock/GatewayMock.sol";
import "forge-std/Test.sol";

contract AxelarEVMRouterTest is Test {
    AxelarGatewayMock axelarGateway;
    GatewayMock gateway;
    AxelarEVMRouter router;

    string private constant axelarCentrifugeChainId = "Moonbeam";
    string private constant axelarCentrifugeChainAddress = "0x3b4a32efd7bd0290882B4854c86b8CECe534c975";

    function setUp() public {
        axelarGateway = new AxelarGatewayMock();
        gateway = new GatewayMock();

        router = new AxelarEVMRouter(address(axelarGateway));
        router.file("gateway", address(gateway));
    }

    function testInvalidFile() public {
        vm.expectRevert("AxelarEVMRouter/file-unrecognized-param");
        router.file("not-gateway", address(1));
    }

    function testFile(address invalidOrigin, address anotherGateway) public {
        vm.assume(invalidOrigin != address(this));

        vm.prank(invalidOrigin);
        vm.expectRevert(bytes("Auth/not-authorized"));
        router.file("gateway", anotherGateway);

        router.file("gateway", anotherGateway);
        assertEq(address(router.gateway()), anotherGateway);
    }

    function testIncomingCalls(
        bytes32 commandId,
        string calldata sourceChain,
        string calldata sourceAddress,
        bytes calldata payload,
        address invalidOrigin,
        string memory invalidAxelarCentrifugeChainId
    ) public {
        vm.assume(invalidOrigin != address(axelarGateway));
        vm.assume(
            keccak256(abi.encodePacked(invalidAxelarCentrifugeChainId))
                != keccak256(abi.encodePacked(axelarCentrifugeChainId))
        );

        vm.expectRevert(bytes("AxelarEVMRouter/invalid-origin"));
        router.execute(commandId, sourceChain, sourceAddress, payload);

        vm.prank(address(axelarGateway));
        vm.expectRevert(bytes("AxelarEVMRouter/invalid-source-chain"));
        router.execute(commandId, sourceChain, sourceAddress, payload);

        axelarGateway.setReturn("validateContractCall", false);
        vm.prank(address(axelarGateway));
        vm.expectRevert(bytes("EVMRouter/not-approved-by-gateway"));
        router.execute(commandId, axelarCentrifugeChainId, sourceAddress, payload);

        axelarGateway.setReturn("validateContractCall", true);
        vm.prank(address(axelarGateway));
        router.execute(commandId, axelarCentrifugeChainId, sourceAddress, payload);
    }

    function testOutgoingCalls(bytes calldata message, address invalidOrigin) public {
        vm.assume(invalidOrigin != address(gateway));

        vm.expectRevert(bytes("AxelarEVMRouter/only-gateway-allowed-to-call"));
        router.send(message);

        vm.prank(address(gateway));
        router.send(message);

        assertEq(axelarGateway.values_string("destinationChain"), axelarCentrifugeChainId);
        assertEq(axelarGateway.values_string("contractAddress"), axelarCentrifugeChainAddress);
        assertEq(axelarGateway.values_bytes("payload"), message);
    }
}
