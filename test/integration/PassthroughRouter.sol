// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import {Auth} from "./../../src/Auth.sol";

interface PrecompileLike {
    function execute(
        bytes32 commandId,
        string calldata sourceChain,
        string calldata sourceAddress,
        bytes calldata payload
    ) external;
}

interface GatewayLike {
    function handle(bytes memory message) external;
}

/// @title  PassthroughRouter
/// @notice Routing contract that accepts any incomming messages and forwards them
///         to the gateway and solely emits an event for outgoing messages.
contract PassthroughRouter is Auth {
    address internal constant PRECOMPILE = 0x0000000000000000000000000000000000000800;
    bytes32 internal constant FAKE_COMMAND_ID = keccak256("FAKE_COMMAND_ID");

    GatewayLike public gateway;

    event RouteToDomain(string destinationChain, string destinationContractAddress, bytes payload);
    event RouteToCentrifuge(string sourceChain, string sourceAddress, bytes payload);
    event ExecuteOnDomain(string destinationChain, string destinationContractAddress, bytes payload);
    event ExecuteOnCentrifuge(string sourceChain, string sourceAddress, bytes payload);

    event File(bytes32 indexed what, address addr);

    function file(bytes32 what, address addr) external {
        if (what == "gateway") {
            gateway = GatewayLike(addr);
        } else {
            revert("LocalRouter/file-unrecognized-param");
        }

        emit File(what, addr);
    }

    /// @notice From Centrifuge to LP on other domain. Just emits an event.
    ///         Just used on Centrifuge.
    function callContract(
        string calldata destinationChain,
        string calldata destinationContractAddress,
        bytes calldata payload
    ) public {
        emit RouteToDomain(destinationChain, destinationContractAddress, payload);
    }

    /// @notice From other domain to Centrifuge. Just emits an event.
    ///         Just used on EVM domains.
    function send(bytes calldata message) public {
        emit RouteToCentrifuge("LP-EVM-Domain", "Passthrough-Contract", message);
    }

    /// @notice Execute message on centrifuge
    function executeOnCentrifuge(string calldata sourceChain, string calldata sourceAddress, bytes calldata payload)
        external
    {
        PrecompileLike precompile = PrecompileLike(PRECOMPILE);
        precompile.execute(FAKE_COMMAND_ID, sourceChain, sourceAddress, payload);

        emit ExecuteOnCentrifuge(sourceChain, sourceAddress, payload);
    }

    /// @notice Execute message on other domain
    function executeOnOtherDomain(
        string calldata destinationChain,
        string calldata destinationContractAddress,
        bytes calldata payload
    ) external {
        gateway.handle(payload);
        emit ExecuteOnDomain(destinationChain, destinationContractAddress, payload);
    }

    // Added to be ignored in coverage report
    function test() public {}
}
