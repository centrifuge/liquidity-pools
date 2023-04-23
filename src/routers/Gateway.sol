// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.18;
pragma abicoder v2;

import {TypedMemView} from "memview-sol/TypedMemView.sol";
import {ConnectorMessages} from "../Messages.sol";

interface ConnectorLike {
    function addCurrency(uint128 currency, address currencyAddress) external;
    function addPool(uint64 poolId) external;
    function allowPoolCurrency(uint128 currency, uint64 poolId) external;
    function addTranche(
        uint64 poolId,
        bytes16 trancheId,
        string memory tokenName,
        string memory tokenSymbol,
        uint8 decimals,
        uint128 price
    ) external;
    function updateMember(uint64 poolId, bytes16 trancheId, address user, uint64 validUntil) external;
    function updateTokenPrice(uint64 poolId, bytes16 trancheId, uint128 price) external;
    function handleTransfer(uint128 currency, address recipient, uint128 amount) external;
    function handleTransferTrancheTokens(
        uint64 poolId,
        bytes16 trancheId,
        uint64 destinationChainId,
        address destinationAddress,
        uint128 amount
    ) external;
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
    function transferTrancheTokensToCentrifuge(
        uint64 poolId,
        bytes16 trancheId,
        address sender,
        bytes32 destinationAddress,
        uint128 amount
    ) public onlyConnector {
        router.send(
            ConnectorMessages.formatTransferTrancheTokens(
                poolId,
                trancheId,
                addressToBytes32(sender),
                ConnectorMessages.formatDomain(ConnectorMessages.Domain.Centrifuge),
                destinationAddress,
                amount
            )
        );
    }

    function transferTrancheTokensToEVM(
        uint64 poolId,
        bytes16 trancheId,
        address sender,
        uint64 destinationChainId,
        address destinationAddress,
        uint128 amount
    ) public onlyConnector {
        router.send(
            ConnectorMessages.formatTransferTrancheTokens(
                poolId,
                trancheId,
                addressToBytes32(sender),
                ConnectorMessages.formatDomain(ConnectorMessages.Domain.EVM, destinationChainId),
                destinationAddress,
                amount
            )
        );
    }

    function transfer(uint128 token, address sender, bytes32 receiver, uint128 amount) public onlyConnector {
        router.send(ConnectorMessages.formatTransfer(token, addressToBytes32(sender), receiver, amount));
    }

    function increaseInvestOrder(uint64 poolId, bytes16 trancheId, address investor, uint128 currency, uint128 amount)
        public
        onlyConnector
    {
        router.send(
            ConnectorMessages.formatIncreaseInvestOrder(poolId, trancheId, addressToBytes32(investor), currency, amount)
        );
    }

    function decreaseInvestOrder(uint64 poolId, bytes16 trancheId, address investor, uint128 currency, uint128 amount)
        public
        onlyConnector
    {
        router.send(
            ConnectorMessages.formatDecreaseInvestOrder(poolId, trancheId, addressToBytes32(investor), currency, amount)
        );
    }

    function increaseRedeemOrder(uint64 poolId, bytes16 trancheId, address investor, uint128 currency, uint128 amount)
        public
        onlyConnector
    {
        router.send(
            ConnectorMessages.formatIncreaseRedeemOrder(poolId, trancheId, addressToBytes32(investor), currency, amount)
        );
    }

    function decreaseRedeemOrder(uint64 poolId, bytes16 trancheId, address investor, uint128 currency, uint128 amount)
        public
        onlyConnector
    {
        router.send(
            ConnectorMessages.formatDecreaseRedeemOrder(poolId, trancheId, addressToBytes32(investor), currency, amount)
        );
    }

    function collectRedeem(uint64 poolId, bytes16 trancheId, address caller) public onlyConnector {
        router.send(ConnectorMessages.formatCollectRedeem(poolId, trancheId, addressToBytes32(caller)));
    }

    function collectInvest(uint64 poolId, bytes16 trancheId, address caller) public onlyConnector {
        router.send(ConnectorMessages.formatCollectInvest(poolId, trancheId, addressToBytes32(caller)));
    }

    // --- Incoming ---
    function handle(bytes memory _message) external onlyRouter {
        bytes29 _msg = _message.ref(0);

        if (ConnectorMessages.isAddCurrency(_msg)) {
            (uint128 currency, address currencyAddress) = ConnectorMessages.parseAddCurrency(_msg);
            connector.addCurrency(currency, currencyAddress);
        } else if (ConnectorMessages.isAddPool(_msg)) {
            (uint64 poolId) = ConnectorMessages.parseAddPool(_msg);
            connector.addPool(poolId);
        } else if (ConnectorMessages.isAllowPoolCurrency(_msg)) {
            (uint128 currency, uint64 poolId) = ConnectorMessages.parseAllowPoolCurrency(_msg);
            connector.allowPoolCurrency(currency, poolId);
        } else if (ConnectorMessages.isAddTranche(_msg)) {
            (
                uint64 poolId,
                bytes16 trancheId,
                string memory tokenName,
                string memory tokenSymbol,
                uint8 decimals,
                uint128 price
            ) = ConnectorMessages.parseAddTranche(_msg);
            connector.addTranche(poolId, trancheId, tokenName, tokenSymbol, decimals, price);
        } else if (ConnectorMessages.isUpdateMember(_msg)) {
            (uint64 poolId, bytes16 trancheId, address user, uint64 validUntil) =
                ConnectorMessages.parseUpdateMember(_msg);
            connector.updateMember(poolId, trancheId, user, validUntil);
        } else if (ConnectorMessages.isUpdateTrancheTokenPrice(_msg)) {
            (uint64 poolId, bytes16 trancheId, uint128 price) = ConnectorMessages.parseUpdateTrancheTokenPrice(_msg);
            connector.updateTokenPrice(poolId, trancheId, price);
        } else if (ConnectorMessages.isTransfer(_msg)) {
            (uint128 currency, address recipient, uint128 amount) = ConnectorMessages.parseIncomingTransfer(_msg);
            connector.handleTransfer(currency, recipient, amount);
        } else if (ConnectorMessages.isTransferTrancheTokens(_msg)) {
            (uint64 poolId, bytes16 trancheId, bytes9 decodedDomain, address destinationAddress, uint128 amount)
            = ConnectorMessages.parseTransferTrancheTokens20(_msg);
            // todo(nuno): pass correct chainId here
            connector.handleTransferTrancheTokens(poolId, trancheId, uint64(block.chainid), destinationAddress, amount);
        } else {
            revert("ConnectorGateway/invalid-message");
        }
    }

    // Utils
    function addressToBytes32(address x) private pure returns (bytes32) {
        return bytes32(bytes20(x));
    }
}
