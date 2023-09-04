// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import {AxelarEVMRouter} from "src/gateway/routers/axelar/EVMRouter.sol";
import {AxelarGatewayMock} from "../../../mock/AxelarGatewayMock.sol";
import {GatewayMock} from "../../../mock/GatewayMock.sol";
import "forge-std/Test.sol";
import "forge-std/console.sol";

contract AxelarEVMRouterTest is Test {
    AxelarGatewayMock axelarGateway;
    GatewayMock gateway;
    AxelarEVMRouter router;

    string private constant axelarCentrifugeChainId = "Moonbeam";

    function setUp() public {
        axelarGateway = new AxelarGatewayMock();
        gateway = new GatewayMock();

        router = new AxelarEVMRouter(address(axelarGateway));
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
        vm.assume(keccak256(abi.encodePacked(invalidAxelarCentrifugeChainId)) != keccak256(abi.encodePacked(axelarCentrifugeChainId)));
        
        vm.expectRevert(bytes("AxelarEVMRouter/invalid-origin"));
        router.execute(commandId, sourceChain, sourceAddress, payload);

        vm.prank(address(axelarGateway));
        vm.expectRevert(bytes("AxelarEVMRouter/invalid-source-chain"));
        router.execute(commandId, sourceChain, sourceAddress, payload);

        console.log(address(router.axelarGateway()));

        vm.expectRevert(bytes("EVMRouter/not-approved-by-gateway"));
        router.execute(commandId, axelarCentrifugeChainId, sourceAddress, payload);

        axelarGateway.setReturn("validateContractCall", true);
        router.execute(commandId, axelarCentrifugeChainId, sourceAddress, payload);
    }
}
