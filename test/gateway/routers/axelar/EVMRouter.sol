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

    function setUp() public {
        axelarGateway = new AxelarGatewayMock();
        gateway = new GatewayMock();

        router = new AxelarEVMRouter(address(axelarGateway));
        router.file("gateway", address(gateway));
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
}
