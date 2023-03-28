// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.18;
pragma abicoder v2;

import {TypedMemView} from "memview-sol/TypedMemView.sol";
import {ConnectorMessages} from "../Messages.sol";

interface ConnectorLike {
    function addPool(uint64 poolId) external;
    function addTranche(
        uint64 poolId,
        bytes16 trancheId,
        string memory tokenName,
        string memory tokenSymbol,
        uint128 price
    ) external;
    function updateMember(uint64 poolId, bytes16 trancheId, address user, uint64 validUntil) external;
    function updateTokenPrice(uint64 poolId, bytes16 trancheId, uint128 price) external;
    function handleTransfer(uint64 poolId, bytes16 trancheId, address destinationAddress, uint128 amount) external;
}

interface RouterLike {
    function send(bytes memory message) external;
}

contract ConnectorGateway {
    using TypedMemView for bytes;
    // why bytes29? - https://github.com/summa-tx/memview-sol#why-bytes29
    using TypedMemView for bytes29;
    using ConnectorMessages for bytes29;

    mapping(address => uint256) public wards;

    ConnectorLike public immutable connector;
    // TODO: support multiple incoming routers (just a single outgoing router) to simplify router migrations
    RouterLike public immutable router;

    /// --- Events ---
    event Rely(address indexed user);
    event Deny(address indexed user);
    event File(bytes32 indexed what, address addr);

    constructor(address connector_, address router_) {
        connector = ConnectorLike(connector_);
        router = RouterLike(router_);

        wards[msg.sender] = 1;
        emit Rely(msg.sender);
    }

    modifier auth() {
        require(wards[msg.sender] == 1, "ConnectorGateway/not-authorized");
        _;
    }

    modifier onlyConnector() {
        require(msg.sender == address(connector), "ConnectorGateway/only-connector-allowed-to-call");
        _;
    }

    modifier onlyRouter() {
        require(msg.sender == address(router), "ConnectorGateway/only-router-allowed-to-call");
        _;
    }

    // --- Administration ---
    function rely(address user) external auth {
        wards[user] = 1;
        emit Rely(user);
    }

    function deny(address user) external auth {
        wards[user] = 0;
        emit Deny(user);
    }

    // --- Outgoing ---
    function transferToCentrifuge(
        uint64 poolId,
        bytes16 trancheId,
        bytes32 destinationAddress,
        uint128 amount
    ) public onlyConnector {
        router.send(
            ConnectorMessages.formatTransfer(
                poolId, trancheId, ConnectorMessages.formatDomain(ConnectorMessages.Domain.Centrifuge), destinationAddress, uint(0), amount
            )
        );
    }

    function transferToEVM(
        uint64 poolId,
        bytes16 trancheId,
        address destinationAddress,
        uint256 chainId,
        uint128 amount
    ) public onlyConnector {
        router.send(
            ConnectorMessages.formatTransfer(
                poolId, trancheId, ConnectorMessages.formatDomain(ConnectorMessages.Domain.EVM), destinationAddress, chainId, amount
            )
        );
    }

    // --- Incoming ---
    function handle(bytes memory _message) external onlyRouter {
        bytes29 _msg = _message.ref(0);
        if (ConnectorMessages.isAddPool(_msg)) {
            uint64 poolId = ConnectorMessages.parseAddPool(_msg);
            connector.addPool(poolId);
        } else if (ConnectorMessages.isAddTranche(_msg)) {
            (uint64 poolId, bytes16 trancheId, string memory tokenName, string memory tokenSymbol, uint128 price) =
                ConnectorMessages.parseAddTranche(_msg);
            connector.addTranche(poolId, trancheId, tokenName, tokenSymbol, price);
        } else if (ConnectorMessages.isUpdateMember(_msg)) {
            (uint64 poolId, bytes16 trancheId, address user, uint64 validUntil) =
                ConnectorMessages.parseUpdateMember(_msg);
            connector.updateMember(poolId, trancheId, user, validUntil);
        } else if (ConnectorMessages.isUpdateTokenPrice(_msg)) {
            (uint64 poolId, bytes16 trancheId, uint128 price) = ConnectorMessages.parseUpdateTokenPrice(_msg);
            connector.updateTokenPrice(poolId, trancheId, price);
        } else if (ConnectorMessages.isTransfer(_msg)) {
            (uint64 poolId, bytes16 trancheId,, address destinationAddress, uint128 amount) =
                ConnectorMessages.parseTransfer20(_msg);
            connector.handleTransfer(poolId, trancheId, destinationAddress, amount);
        } else {
            revert("ConnectorGateway/invalid-message");
        }
    }
}
