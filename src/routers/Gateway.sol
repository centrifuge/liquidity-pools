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
}

interface RouterLike {
    function send(bytes memory message) external;
}

interface AdminLike {
    function pause() external;
    function unpause() external;
}

interface DelayedAdminLike {
    function scheduleRely48hr(address spell) external;
    function cancelSchedule(address spell) external;
}

interface AuthLike {
    function rely(address usr) external;
}

contract ConnectorGateway{
    using TypedMemView for bytes;
    // why bytes29? - https://github.com/summa-tx/memview-sol#why-bytes29
    using TypedMemView for bytes29;
    using ConnectorMessages for bytes29;

    mapping(address => uint256) public wards;
    mapping(address => uint256) public relySchedule;
    uint256 public constant GRACE_PERIOD = 48 hours;
    bool public paused = false;

    ConnectorLike public immutable connector;
    // TODO: support multiple incoming routers (just a single outgoing router) to simplify router migrations
    RouterLike public immutable router;
    AdminLike public immutable pauseAdmin;
    DelayedAdminLike public immutable delayedAdmin;

    /// --- Events ---
    event Rely(address indexed user);
    event Deny(address indexed user);
    event File(bytes32 indexed what, address addr);

    constructor(address connector_, address router_, address pauseAdmin_, address delayedAdmin_) {
        connector = ConnectorLike(connector_);
        router = RouterLike(router_);
        pauseAdmin = AdminLike(pauseAdmin_);
        delayedAdmin = DelayedAdminLike(delayedAdmin_);

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

    modifier onlyPauseAdmin() {
        require(msg.sender == address(pauseAdmin), "ConnectorGateway/not-pause-admin");
        _;
    }

    modifier onlyDelayedAdmin() {
        require(msg.sender == address(delayedAdmin), "ConnectorGateway/not-delayed-admin");
        _;
    }

    modifier onlyAdmins() {
        require(msg.sender == address(delayedAdmin) || msg.sender == address(pauseAdmin), "ConnectorGateway/not-admin");
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

    function pause() external onlyPauseAdmin {
        paused = true;
    }

    function unpause() external onlyPauseAdmin {
        paused = false;
    }

    function scheduleRely24hr(address spell) internal {
        relySchedule[spell] = block.timestamp + 24 hours;
    }

    function scheduleRely48hr(address spell) external onlyDelayedAdmin {
        relySchedule[spell] = block.timestamp + 48 hours;
    }

    function cancelSchedule(address spell) external onlyAdmins {
        relySchedule[spell] = 0;
    }

    function relySpell(address spell) public {
        require(relySchedule[spell] != 0, "ConnectorGateway/spell-not-scheduled");
        require(relySchedule[spell] < block.timestamp, "ConnectorGateway/spell-not-ready");
        require(relySchedule[spell] + GRACE_PERIOD > block.timestamp, "ConnectorGateway/spell-too-old");
        relySchedule[spell] = 0;
        wards[spell] = 1;
        emit Rely(spell);
    }

    function relyContract(address target, address usr) public auth {
        AuthLike(target).rely(usr);
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
        } else {
            revert("ConnectorGateway/invalid-message");
        }
    }

    // Utils
    function addressToBytes32(address x) private pure returns (bytes32) {
        return bytes32(bytes20(x));
    }
}
