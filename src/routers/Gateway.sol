// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.18;
pragma abicoder v2;

import {TypedMemView} from "memview-sol/TypedMemView.sol";
import {ConnectorMessages} from "../Messages.sol";

interface ConnectorLike {
    function addCurrency(uint128 currency, address currencyAddress) external;
    function addPool(uint64 poolId) external;
    function allowPoolCurrency(uint64 poolId, uint128 currency) external;
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
    function handleTransferTrancheTokens(uint64 poolId, bytes16 trancheId, address destinationAddress, uint128 amount)
        external;
    function handleExecutedDecreaseInvestOrder(
        uint64 poolId,
        bytes16 trancheId,
        bytes32 investor,
        uint128 currency,
        uint128 currencyPayout,
        uint128 remainingInvestOrder
    ) external;
    function handleExecutedDecreaseRedeemOrder(
        uint64 poolId,
        bytes16 trancheId,
        bytes32 investor,
        uint128 currency,
        uint128 trancheTokensPayout,
        uint128 remainingRedeemOrder
    ) external;
    function handleExecutedCollectInvest(
        uint64 poolId,
        bytes16 trancheId,
        bytes32 investor,
        uint128 currency,
        uint128 currencyPayout,
        uint128 trancheTokensPayout,
        uint128 remainingInvestOrder
    ) external;
    function handleExecutedCollectRedeem(
        uint64 poolId,
        bytes16 trancheId,
        bytes32 investor,
        uint128 currency,
        uint128 currencyPayout,
        uint128 trancheTokensPayout,
        uint128 remainingRedeemOrder
    ) external;
}

interface RouterLike {
    function send(bytes memory message) external;
}

interface AuthLike {
    function rely(address usr) external;
}

contract ConnectorGateway {
    using TypedMemView for bytes;
    // why bytes29? - https://github.com/summa-tx/memview-sol#why-bytes29
    using TypedMemView for bytes29;
    using ConnectorMessages for bytes29;

    mapping(address => uint256) public wards;
    mapping(address => uint256) public relySchedule;
    uint256 public immutable shortScheduleWait;
    uint256 public immutable longScheduleWait;
    // gracePeriod is the time after a user is scheduled to be relied that they can still be relied
    uint256 public immutable gracePeriod;
    bool public paused = false;

    ConnectorLike public immutable connector;
    // TODO: support multiple incoming routers (just a single outgoing router) to simplify router migrations
    RouterLike public immutable router;

    /// --- Events ---
    event Rely(address indexed user);
    event Deny(address indexed user);
    event File(bytes32 indexed what, address addr);
    event RelyScheduledShort(address indexed spell, uint256 indexed scheduledTime);
    event RelyScheduledLong(address indexed spell, uint256 indexed scheduledTime);
    event RelyCancelled(address indexed spell);
    event Pause();
    event Unpause();

    constructor(
        address connector_,
        address router_,
        uint256 shortScheduleWait_,
        uint256 longScheduleWait_,
        uint256 gracePeriod_
    ) {
        connector = ConnectorLike(connector_);
        router = RouterLike(router_);
        shortScheduleWait = shortScheduleWait_;
        longScheduleWait = longScheduleWait_;
        gracePeriod = gracePeriod_;

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

    modifier pauseable() {
        require(!paused, "ConnectorGateway/paused");
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

    function pause() external auth {
        paused = true;
        emit Pause();
    }

    function unpause() external auth {
        paused = false;
        emit Unpause();
    }

    function scheduleShortRely(address user) internal {
        relySchedule[user] = block.timestamp + shortScheduleWait;
        emit RelyScheduledShort(user, relySchedule[user]);
    }

    function scheduleLongRely(address user) external auth {
        relySchedule[user] = block.timestamp + longScheduleWait;
        emit RelyScheduledLong(user, relySchedule[user]);
    }

    function cancelSchedule(address user) external auth {
        relySchedule[user] = 0;
        emit RelyCancelled(user);
    }

    function executeScheduledRely(address user) public {
        require(relySchedule[user] != 0, "ConnectorGateway/user-not-scheduled");
        require(relySchedule[user] < block.timestamp, "ConnectorGateway/user-not-ready");
        require(relySchedule[user] + gracePeriod > block.timestamp, "ConnectorGateway/user-too-old");
        relySchedule[user] = 0;
        wards[user] = 1;
        emit Rely(user);
    }

    function relyContract(address target, address user) public auth {
        AuthLike(target).rely(user);
    }

    // --- Outgoing ---
    function transferTrancheTokensToCentrifuge(
        uint64 poolId,
        bytes16 trancheId,
        address sender,
        bytes32 destinationAddress,
        uint128 amount
    ) public onlyConnector pauseable {
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
    ) public onlyConnector pauseable {
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

    function transfer(uint128 token, address sender, bytes32 receiver, uint128 amount) public onlyConnector pauseable {
        router.send(ConnectorMessages.formatTransfer(token, addressToBytes32(sender), receiver, amount));
    }

    function increaseInvestOrder(uint64 poolId, bytes16 trancheId, address investor, uint128 currency, uint128 amount)
        public
        onlyConnector
        pauseable
    {
        router.send(
            ConnectorMessages.formatIncreaseInvestOrder(poolId, trancheId, addressToBytes32(investor), currency, amount)
        );
    }

    function decreaseInvestOrder(uint64 poolId, bytes16 trancheId, address investor, uint128 currency, uint128 amount)
        public
        onlyConnector
        pauseable
    {
        router.send(
            ConnectorMessages.formatDecreaseInvestOrder(poolId, trancheId, addressToBytes32(investor), currency, amount)
        );
    }

    function increaseRedeemOrder(uint64 poolId, bytes16 trancheId, address investor, uint128 currency, uint128 amount)
        public
        onlyConnector
        pauseable
    {
        router.send(
            ConnectorMessages.formatIncreaseRedeemOrder(poolId, trancheId, addressToBytes32(investor), currency, amount)
        );
    }

    function decreaseRedeemOrder(uint64 poolId, bytes16 trancheId, address investor, uint128 currency, uint128 amount)
        public
        onlyConnector
        pauseable
    {
        router.send(
            ConnectorMessages.formatDecreaseRedeemOrder(poolId, trancheId, addressToBytes32(investor), currency, amount)
        );
    }

    function collectInvest(uint64 poolId, bytes16 trancheId, address investor) public onlyConnector pauseable {
        router.send(ConnectorMessages.formatCollectInvest(poolId, trancheId, addressToBytes32(investor)));
    }

    function collectRedeem(uint64 poolId, bytes16 trancheId, address investor) public onlyConnector pauseable {
        router.send(ConnectorMessages.formatCollectRedeem(poolId, trancheId, addressToBytes32(investor)));
    }

    // --- Incoming ---
    function handle(bytes memory _message) external onlyRouter pauseable {
        bytes29 _msg = _message.ref(0);

        if (ConnectorMessages.isAddCurrency(_msg)) {
            (uint128 currency, address currencyAddress) = ConnectorMessages.parseAddCurrency(_msg);
            connector.addCurrency(currency, currencyAddress);
        } else if (ConnectorMessages.isAddPool(_msg)) {
            (uint64 poolId) = ConnectorMessages.parseAddPool(_msg);
            connector.addPool(poolId);
        } else if (ConnectorMessages.isAllowPoolCurrency(_msg)) {
            (uint64 poolId, uint128 currency) = ConnectorMessages.parseAllowPoolCurrency(_msg);
            connector.allowPoolCurrency(poolId, currency);
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
            (uint64 poolId, bytes16 trancheId, address destinationAddress, uint128 amount) =
                ConnectorMessages.parseTransferTrancheTokens20(_msg);
            connector.handleTransferTrancheTokens(poolId, trancheId, destinationAddress, amount);
        } else if (ConnectorMessages.isExecutedDecreaseInvestOrder(_msg)) {
            (
                uint64 poolId,
                bytes16 trancheId,
                bytes32 investor,
                uint128 currency,
                uint128 currencyPayout,
                uint128 remainingInvestOrder
            ) = ConnectorMessages.parseExecutedDecreaseInvestOrder(_msg);
            connector.handleExecutedDecreaseInvestOrder(
                poolId, trancheId, investor, currency, currencyPayout, remainingInvestOrder
            );
        } else if (ConnectorMessages.isExecutedDecreaseRedeemOrder(_msg)) {
            (
                uint64 poolId,
                bytes16 trancheId,
                bytes32 investor,
                uint128 currency,
                uint128 trancheTokensPayout,
                uint128 remainingRedeemOrder
            ) = ConnectorMessages.parseExecutedDecreaseRedeemOrder(_msg);
            connector.handleExecutedDecreaseRedeemOrder(
                poolId, trancheId, investor, currency, trancheTokensPayout, remainingRedeemOrder
            );
        } else if (ConnectorMessages.isExecutedCollectInvest(_msg)) {
            (
                uint64 poolId,
                bytes16 trancheId,
                bytes32 investor,
                uint128 currency,
                uint128 currencyPayout,
                uint128 trancheTokensPayout,
                uint128 remainingInvestOrder
            ) = ConnectorMessages.parseExecutedCollectInvest(_msg);
            connector.handleExecutedCollectInvest(
                poolId, trancheId, investor, currency, currencyPayout, trancheTokensPayout, remainingInvestOrder
            );
        } else if (ConnectorMessages.isExecutedCollectRedeem(_msg)) {
            (
                uint64 poolId,
                bytes16 trancheId,
                bytes32 investor,
                uint128 currency,
                uint128 currencyPayout,
                uint128 trancheTokensRedeemed,
                uint128 remainingRedeemOrder
            ) = ConnectorMessages.parseExecutedCollectRedeem(_msg);
            connector.handleExecutedCollectRedeem(
                poolId, trancheId, investor, currency, currencyPayout, trancheTokensRedeemed, remainingRedeemOrder
            );
        } else if (ConnectorMessages.isAddAdmin(_msg)) {
            address spell = ConnectorMessages.parseAddAdmin(_msg);
            scheduleShortRely(spell);
        } else {
            revert("ConnectorGateway/invalid-message");
        }
    }

    // Utils
    function addressToBytes32(address x) private pure returns (bytes32) {
        return bytes32(bytes20(x));
    }
}
