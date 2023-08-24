// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.18;
pragma abicoder v2;

import {TypedMemView} from "memview-sol/TypedMemView.sol";
import {Messages} from "./Messages.sol";

interface InvestmentManagerLike {
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
    function handleExecutedDecreaseInvestOrder(
        uint64 poolId,
        bytes16 trancheId,
        address investor,
        uint128 currency,
        uint128 currencyPayout
    ) external;
    function handleExecutedDecreaseRedeemOrder(
        uint64 poolId,
        bytes16 trancheId,
        address investor,
        uint128 currency,
        uint128 trancheTokensPayout
    ) external;
    function handleExecutedCollectInvest(
        uint64 poolId,
        bytes16 trancheId,
        address investor,
        uint128 currency,
        uint128 currencyPayout,
        uint128 trancheTokensPayout
    ) external;
    function handleExecutedCollectRedeem(
        uint64 poolId,
        bytes16 trancheId,
        address investor,
        uint128 currency,
        uint128 currencyPayout,
        uint128 trancheTokensPayout
    ) external;
}

interface TokenManagerLike {
    function addCurrency(uint128 currency, address currencyAddress) external;
    function handleTransfer(uint128 currency, address recipient, uint128 amount) external;
    function handleTransferTrancheTokens(
        uint64 poolId,
        bytes16 trancheId,
        uint128 currency,
        address destinationAddress,
        uint128 amount
    ) external;
}

interface RouterLike {
    function send(bytes memory message) external;
}

interface AuthLike {
    function rely(address usr) external;
}

contract Gateway {
    using TypedMemView for bytes;
    // why bytes29? - https://github.com/summa-tx/memview-sol#why-bytes29
    using TypedMemView for bytes29;
    using Messages for bytes29;

    mapping(address => uint256) public wards;
    mapping(address => uint256) public relySchedule;
    uint256 public immutable shortScheduleWait;
    uint256 public immutable longScheduleWait;
    // gracePeriod is the time after a user is scheduled to be relied that they can still be relied
    uint256 public immutable gracePeriod;
    bool public paused = false;

    InvestmentManagerLike public immutable investmentManager;
    TokenManagerLike public immutable tokenManager;
    mapping(address => bool) public incomingRouters;
    RouterLike public outgoingRouter;

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
        address investmentManager_,
        address tokenManager_,
        address router_,
        uint256 shortScheduleWait_,
        uint256 longScheduleWait_,
        uint256 gracePeriod_
    ) {
        investmentManager = InvestmentManagerLike(investmentManager_);
        tokenManager = TokenManagerLike(tokenManager_);
        incomingRouters[router_] = true;
        outgoingRouter = RouterLike(router_);

        shortScheduleWait = shortScheduleWait_;
        longScheduleWait = longScheduleWait_;
        gracePeriod = gracePeriod_;

        wards[msg.sender] = 1;
        emit Rely(msg.sender);
    }

    modifier auth() {
        require(wards[msg.sender] == 1, "Gateway/not-authorized");
        _;
    }

    modifier onlyInvestmentManager() {
        require(msg.sender == address(investmentManager), "Gateway/only-investmentManager-allowed-to-call");
        _;
    }

    modifier onlyRouter() {
        require(incomingRouters[msg.sender] == true, "Gateway/only-router-allowed-to-call");
        _;
    }

    modifier pauseable() {
        require(!paused, "Gateway/paused");
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

    function addIncomingRouter(address router) internal {
        incomingRouters[router] = true;
    }

    function removeIncomingRouter(address router) internal {
        incomingRouters[router] = false;
    }

    function setOutgoingRouter(address router) internal {
        outgoingRouter = RouterLike(router);
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
        require(relySchedule[user] != 0, "Gateway/user-not-scheduled");
        require(relySchedule[user] < block.timestamp, "Gateway/user-not-ready");
        require(relySchedule[user] + gracePeriod > block.timestamp, "Gateway/user-too-old");
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
        uint128 currencyId,
        uint128 amount
    ) public onlyInvestmentManager pauseable {
        outgoingRouter.send(
            Messages.formatTransferTrancheTokens(
                poolId,
                trancheId,
                addressToBytes32(sender),
                Messages.formatDomain(Messages.Domain.Centrifuge),
                currencyId,
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
        uint128 currencyId,
        address destinationAddress,
        uint128 amount
    ) public onlyInvestmentManager pauseable {
        outgoingRouter.send(
            Messages.formatTransferTrancheTokens(
                poolId,
                trancheId,
                addressToBytes32(sender),
                Messages.formatDomain(Messages.Domain.EVM, destinationChainId),
                currencyId,
                destinationAddress,
                amount
            )
        );
    }

    function transfer(uint128 token, address sender, bytes32 receiver, uint128 amount)
        public
        onlyInvestmentManager
        pauseable
    {
        outgoingRouter.send(Messages.formatTransfer(token, addressToBytes32(sender), receiver, amount));
    }

    function increaseInvestOrder(uint64 poolId, bytes16 trancheId, address investor, uint128 currency, uint128 amount)
        public
        onlyInvestmentManager
        pauseable
    {
        outgoingRouter.send(
            Messages.formatIncreaseInvestOrder(poolId, trancheId, addressToBytes32(investor), currency, amount)
        );
    }

    function decreaseInvestOrder(uint64 poolId, bytes16 trancheId, address investor, uint128 currency, uint128 amount)
        public
        onlyInvestmentManager
        pauseable
    {
        outgoingRouter.send(
            Messages.formatDecreaseInvestOrder(poolId, trancheId, addressToBytes32(investor), currency, amount)
        );
    }

    function increaseRedeemOrder(uint64 poolId, bytes16 trancheId, address investor, uint128 currency, uint128 amount)
        public
        onlyInvestmentManager
        pauseable
    {
        outgoingRouter.send(
            Messages.formatDecreaseRedeemOrder(poolId, trancheId, addressToBytes32(investor), currency, amount)
        );
    }

    function collectInvest(uint64 poolId, bytes16 trancheId, address investor, uint128 currency)
        public
        onlyInvestmentManager
        pauseable
    {
        outgoingRouter.send(Messages.formatCollectInvest(poolId, trancheId, addressToBytes32(investor), currency));
    }

    function collectRedeem(uint64 poolId, bytes16 trancheId, address investor, uint128 currency)
        public
        onlyInvestmentManager
        pauseable
    {
        outgoingRouter.send(Messages.formatCollectRedeem(poolId, trancheId, addressToBytes32(investor), currency));
    }

    // --- Incoming ---
    function handle(bytes memory _message) external onlyRouter pauseable {
        bytes29 _msg = _message.ref(0);

        if (Messages.isAddCurrency(_msg)) {
            (uint128 currency, address currencyAddress) = Messages.parseAddCurrency(_msg);
            tokenManager.addCurrency(currency, currencyAddress);
        } else if (Messages.isAddPool(_msg)) {
            (uint64 poolId) = Messages.parseAddPool(_msg);
            investmentManager.addPool(poolId);
        } else if (Messages.isAllowPoolCurrency(_msg)) {
            (uint64 poolId, uint128 currency) = Messages.parseAllowPoolCurrency(_msg);
            investmentManager.allowPoolCurrency(poolId, currency);
        } else if (Messages.isAddTranche(_msg)) {
            (
                uint64 poolId,
                bytes16 trancheId,
                string memory tokenName,
                string memory tokenSymbol,
                uint8 decimals,
                uint128 price
            ) = Messages.parseAddTranche(_msg);
            investmentManager.addTranche(poolId, trancheId, tokenName, tokenSymbol, decimals, price);
        } else if (Messages.isUpdateMember(_msg)) {
            (uint64 poolId, bytes16 trancheId, address user, uint64 validUntil) = Messages.parseUpdateMember(_msg);
            investmentManager.updateMember(poolId, trancheId, user, validUntil);
        } else if (Messages.isUpdateTrancheTokenPrice(_msg)) {
            (uint64 poolId, bytes16 trancheId, uint128 price) = Messages.parseUpdateTrancheTokenPrice(_msg);
            investmentManager.updateTokenPrice(poolId, trancheId, price);
        } else if (Messages.isTransfer(_msg)) {
            (uint128 currency, address recipient, uint128 amount) = Messages.parseIncomingTransfer(_msg);
            tokenManager.handleTransfer(currency, recipient, amount);
        } else if (Messages.isTransferTrancheTokens(_msg)) {
            (uint64 poolId, bytes16 trancheId, uint128 currencyId, address destinationAddress, uint128 amount) =
                Messages.parseTransferTrancheTokens20(_msg);
           tokenManager.handleTransferTrancheTokens(poolId, trancheId, currencyId, destinationAddress, amount);
        } else if (Messages.isExecutedDecreaseInvestOrder(_msg)) {
            (uint64 poolId, bytes16 trancheId, address investor, uint128 currency, uint128 currencyPayout) =
                Messages.parseExecutedDecreaseInvestOrder(_msg);
            investmentManager.handleExecutedDecreaseInvestOrder(poolId, trancheId, investor, currency, currencyPayout);
        } else if (Messages.isExecutedDecreaseRedeemOrder(_msg)) {
            (uint64 poolId, bytes16 trancheId, address investor, uint128 currency, uint128 trancheTokensPayout) =
                Messages.parseExecutedDecreaseRedeemOrder(_msg);
            investmentManager.handleExecutedDecreaseRedeemOrder(
                poolId, trancheId, investor, currency, trancheTokensPayout
            );
        } else if (Messages.isExecutedCollectInvest(_msg)) {
            (
                uint64 poolId,
                bytes16 trancheId,
                address investor,
                uint128 currency,
                uint128 currencyPayout,
                uint128 trancheTokensPayout
            ) = Messages.parseExecutedCollectInvest(_msg);
            investmentManager.handleExecutedCollectInvest(
                poolId, trancheId, investor, currency, currencyPayout, trancheTokensPayout
            );
        } else if (Messages.isExecutedCollectRedeem(_msg)) {
            (
                uint64 poolId,
                bytes16 trancheId,
                address investor,
                uint128 currency,
                uint128 currencyPayout,
                uint128 trancheTokensRedeemed
            ) = Messages.parseExecutedCollectRedeem(_msg);
            investmentManager.handleExecutedCollectRedeem(
                poolId, trancheId, investor, currency, currencyPayout, trancheTokensRedeemed
            );
        } else if (Messages.isScheduleUpgrade(_msg)) {
            address spell = Messages.parseScheduleUpgrade(_msg);
            scheduleShortRely(spell);
        } else {
            revert("Gateway/invalid-message");
        }
    }

    // Utils
    function addressToBytes32(address x) private pure returns (bytes32) {
        return bytes32(bytes20(x));
    }
}
