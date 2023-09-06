// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import {Messages} from "./Messages.sol";
import {Auth} from "./../util/Auth.sol";

interface InvestmentManagerLike {
    function updateTrancheTokenPrice(uint64 poolId, bytes16 trancheId, uint128 currencyId, uint128 price) external;
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

interface PoolManagerLike {
    function addPool(uint64 poolId) external;
    function allowPoolCurrency(uint64 poolId, uint128 currency) external;
    function addTranche(
        uint64 poolId,
        bytes16 trancheId,
        string memory tokenName,
        string memory tokenSymbol,
        uint8 decimals
    ) external;
    function updateMember(uint64 poolId, bytes16 trancheId, address user, uint64 validUntil) external;
    function updateTrancheTokenMetadata(
        uint64 poolId,
        bytes16 trancheId,
        string memory tokenName,
        string memory tokenSymbol
    ) external;
    function addCurrency(uint128 currency, address currencyAddress) external;
    function handleTransfer(uint128 currency, address recipient, uint128 amount) external;
    function handleTransferTrancheTokens(uint64 poolId, bytes16 trancheId, address destinationAddress, uint128 amount)
        external;
}

interface RouterLike {
    function send(bytes memory message) external;
}

interface AuthLike {
    function rely(address usr) external;
}

interface RootLike {
    function paused() external returns (bool);
    function scheduleRely(address target) external;
    function cancelRely(address target) external;
}

/// @title  Gateway
/// @dev    It parses incoming messages and forwards these to Managers
///         and it encoded outgoing messages and sends these to Routers.
///
///         If the Root is paused, any messages in and out of this contract
///         will not be forwarded
contract Gateway is Auth {
    RootLike public immutable root;
    InvestmentManagerLike public investmentManager;
    PoolManagerLike public poolManager;

    mapping(address => bool) public incomingRouters;
    RouterLike public outgoingRouter;

    // --- Events ---
    event AddIncomingRouter(address indexed router);
    event RemoveIncomingRouter(address indexed router);
    event UpdateOutgoingRouter(address indexed router);
    event File(bytes32 indexed what, address data);

    constructor(address root_, address investmentManager_, address poolManager_, address router_) {
        root = RootLike(root_);
        investmentManager = InvestmentManagerLike(investmentManager_);
        poolManager = PoolManagerLike(poolManager_);
        incomingRouters[router_] = true;
        outgoingRouter = RouterLike(router_);

        wards[msg.sender] = 1;
        emit Rely(msg.sender);
    }

    modifier onlyInvestmentManager() {
        require(msg.sender == address(investmentManager), "Gateway/only-investment-manager-allowed-to-call");
        _;
    }

    modifier onlyPoolManager() {
        require(msg.sender == address(poolManager), "Gateway/only-pool-manager-allowed-to-call");
        _;
    }

    modifier onlyIncomingRouter() {
        require(incomingRouters[msg.sender], "Gateway/only-router-allowed-to-call");
        _;
    }

    modifier pauseable() {
        require(!root.paused(), "Gateway/paused");
        _;
    }

    // --- Administration ---
    function file(bytes32 what, address data) public auth {
        if (what == "poolManager") poolManager = PoolManagerLike(data);
        else if (what == "investmentManager") investmentManager = InvestmentManagerLike(data);
        else revert("Gateway/file-unrecognized-param");
        emit File(what, data);
    }

    function addIncomingRouter(address router) public auth {
        incomingRouters[router] = true;
        emit AddIncomingRouter(router);
    }

    function removeIncomingRouter(address router) public auth {
        incomingRouters[router] = false;
        emit RemoveIncomingRouter(router);
    }

    function updateOutgoingRouter(address router) public auth {
        outgoingRouter = RouterLike(router);
        emit UpdateOutgoingRouter(router);
    }

    // --- Outgoing ---
    function transferTrancheTokensToCentrifuge(
        uint64 poolId,
        bytes16 trancheId,
        address sender,
        bytes32 destinationAddress,
        uint128 amount
    ) public onlyPoolManager pauseable {
        outgoingRouter.send(
            Messages.formatTransferTrancheTokens(
                poolId,
                trancheId,
                _addressToBytes32(sender),
                Messages.formatDomain(Messages.Domain.Centrifuge),
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
    ) public onlyPoolManager pauseable {
        outgoingRouter.send(
            Messages.formatTransferTrancheTokens(
                poolId,
                trancheId,
                _addressToBytes32(sender),
                Messages.formatDomain(Messages.Domain.EVM, destinationChainId),
                destinationAddress,
                amount
            )
        );
    }

    function transfer(uint128 token, address sender, bytes32 receiver, uint128 amount)
        public
        onlyPoolManager
        pauseable
    {
        outgoingRouter.send(Messages.formatTransfer(token, _addressToBytes32(sender), receiver, amount));
    }

    function increaseInvestOrder(
        uint64 poolId,
        bytes16 trancheId,
        address investor,
        uint128 currency,
        uint128 currencyAmount
    ) public onlyInvestmentManager pauseable {
        outgoingRouter.send(
            Messages.formatIncreaseInvestOrder(poolId, trancheId, _addressToBytes32(investor), currency, currencyAmount)
        );
    }

    function decreaseInvestOrder(
        uint64 poolId,
        bytes16 trancheId,
        address investor,
        uint128 currency,
        uint128 currencyAmount
    ) public onlyInvestmentManager pauseable {
        outgoingRouter.send(
            Messages.formatDecreaseInvestOrder(poolId, trancheId, _addressToBytes32(investor), currency, currencyAmount)
        );
    }

    function increaseRedeemOrder(
        uint64 poolId,
        bytes16 trancheId,
        address investor,
        uint128 currency,
        uint128 trancheTokenAmount
    ) public onlyInvestmentManager pauseable {
        outgoingRouter.send(
            Messages.formatIncreaseRedeemOrder(
                poolId, trancheId, _addressToBytes32(investor), currency, trancheTokenAmount
            )
        );
    }

    function decreaseRedeemOrder(
        uint64 poolId,
        bytes16 trancheId,
        address investor,
        uint128 currency,
        uint128 trancheTokenAmount
    ) public onlyInvestmentManager pauseable {
        outgoingRouter.send(
            Messages.formatDecreaseRedeemOrder(
                poolId, trancheId, _addressToBytes32(investor), currency, trancheTokenAmount
            )
        );
    }

    function collectInvest(uint64 poolId, bytes16 trancheId, address investor, uint128 currency)
        public
        onlyInvestmentManager
        pauseable
    {
        outgoingRouter.send(Messages.formatCollectInvest(poolId, trancheId, _addressToBytes32(investor), currency));
    }

    function collectRedeem(uint64 poolId, bytes16 trancheId, address investor, uint128 currency)
        public
        onlyInvestmentManager
        pauseable
    {
        outgoingRouter.send(Messages.formatCollectRedeem(poolId, trancheId, _addressToBytes32(investor), currency));
    }

    function cancelInvestOrder(uint64 poolId, bytes16 trancheId, address investor, uint128 currency)
        public
        onlyInvestmentManager
        pauseable
    {
        outgoingRouter.send(Messages.formatCancelInvestOrder(poolId, trancheId, _addressToBytes32(investor), currency));
    }

    function cancelRedeemOrder(uint64 poolId, bytes16 trancheId, address investor, uint128 currency)
        public
        onlyInvestmentManager
        pauseable
    {
        outgoingRouter.send(Messages.formatCancelRedeemOrder(poolId, trancheId, _addressToBytes32(investor), currency));
    }

    // --- Incoming ---
    function handle(bytes calldata message) external onlyIncomingRouter pauseable {
        if (Messages.isAddCurrency(message)) {
            (uint128 currency, address currencyAddress) = Messages.parseAddCurrency(message);
            poolManager.addCurrency(currency, currencyAddress);
        } else if (Messages.isAddPool(message)) {
            (uint64 poolId) = Messages.parseAddPool(message);
            poolManager.addPool(poolId);
        } else if (Messages.isAllowPoolCurrency(message)) {
            (uint64 poolId, uint128 currency) = Messages.parseAllowPoolCurrency(message);
            poolManager.allowPoolCurrency(poolId, currency);
        } else if (Messages.isAddTranche(message)) {
            (
                uint64 poolId,
                bytes16 trancheId,
                string memory tokenName,
                string memory tokenSymbol,
                uint8 decimals,
                uint128 _price
            ) = Messages.parseAddTranche(message);
            poolManager.addTranche(poolId, trancheId, tokenName, tokenSymbol, decimals);
        } else if (Messages.isUpdateMember(message)) {
            (uint64 poolId, bytes16 trancheId, address user, uint64 validUntil) = Messages.parseUpdateMember(message);
            poolManager.updateMember(poolId, trancheId, user, validUntil);
        } else if (Messages.isUpdateTrancheTokenPrice(message)) {
            (uint64 poolId, bytes16 trancheId, uint128 currencyId, uint128 price) =
                Messages.parseUpdateTrancheTokenPrice(message);
            investmentManager.updateTrancheTokenPrice(poolId, trancheId, currencyId, price);
        } else if (Messages.isTransfer(message)) {
            (uint128 currency, address recipient, uint128 amount) = Messages.parseIncomingTransfer(message);
            poolManager.handleTransfer(currency, recipient, amount);
        } else if (Messages.isTransferTrancheTokens(message)) {
            (uint64 poolId, bytes16 trancheId, address destinationAddress, uint128 amount) =
                Messages.parseTransferTrancheTokens20(message);
            poolManager.handleTransferTrancheTokens(poolId, trancheId, destinationAddress, amount);
        } else if (Messages.isExecutedDecreaseInvestOrder(message)) {
            (uint64 poolId, bytes16 trancheId, address investor, uint128 currency, uint128 currencyPayout) =
                Messages.parseExecutedDecreaseInvestOrder(message);
            investmentManager.handleExecutedDecreaseInvestOrder(poolId, trancheId, investor, currency, currencyPayout);
        } else if (Messages.isExecutedDecreaseRedeemOrder(message)) {
            (uint64 poolId, bytes16 trancheId, address investor, uint128 currency, uint128 trancheTokensPayout) =
                Messages.parseExecutedDecreaseRedeemOrder(message);
            investmentManager.handleExecutedDecreaseRedeemOrder(
                poolId, trancheId, investor, currency, trancheTokensPayout
            );
        } else if (Messages.isExecutedCollectInvest(message)) {
            (
                uint64 poolId,
                bytes16 trancheId,
                address investor,
                uint128 currency,
                uint128 currencyPayout,
                uint128 trancheTokensPayout
            ) = Messages.parseExecutedCollectInvest(message);
            investmentManager.handleExecutedCollectInvest(
                poolId, trancheId, investor, currency, currencyPayout, trancheTokensPayout
            );
        } else if (Messages.isExecutedCollectRedeem(message)) {
            (
                uint64 poolId,
                bytes16 trancheId,
                address investor,
                uint128 currency,
                uint128 currencyPayout,
                uint128 trancheTokensPayout
            ) = Messages.parseExecutedCollectRedeem(message);
            investmentManager.handleExecutedCollectRedeem(
                poolId, trancheId, investor, currency, currencyPayout, trancheTokensPayout
            );
        } else if (Messages.isScheduleUpgrade(message)) {
            address target = Messages.parseScheduleUpgrade(message);
            root.scheduleRely(target);
        } else if (Messages.isCancelUpgrade(message)) {
            address target = Messages.parseCancelUpgrade(message);
            root.cancelRely(target);
        } else if (Messages.isUpdateTrancheTokenMetadata(message)) {
            (uint64 poolId, bytes16 trancheId, string memory tokenName, string memory tokenSymbol) =
                Messages.parseUpdateTrancheTokenMetadata(message);
            poolManager.updateTrancheTokenMetadata(poolId, trancheId, tokenName, tokenSymbol);
        } else {
            revert("Gateway/invalid-message");
        }
    }

    // --- Helpers ---
    function _addressToBytes32(address x) internal pure returns (bytes32) {
        return bytes32(bytes20(x));
    }
}
