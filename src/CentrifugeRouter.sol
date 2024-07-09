// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.26;

import {Auth} from "src/Auth.sol";
import {MathLib} from "src/libraries/MathLib.sol";
import {SafeTransferLib} from "src/libraries/SafeTransferLib.sol";
import {CastLib} from "src/libraries/CastLib.sol";
import {IERC20, IERC20Permit, IERC20Wrapper} from "src/interfaces/IERC20.sol";
import {IERC7540Vault} from "src/interfaces/IERC7540.sol";
import {ICentrifugeRouter} from "src/interfaces/ICentrifugeRouter.sol";
import {IPoolManager, Domain} from "src/interfaces/IPoolManager.sol";
import {IInvestmentManager} from "src/interfaces/IInvestmentManager.sol";
import {IEscrow} from "src/interfaces/IEscrow.sol";
import {IGateway} from "src/interfaces/gateway/IGateway.sol";

interface AuthTransferLike {
    function authTransferFrom(address sender, address owner, address recipient, uint256 amount) external;
}

contract CentrifugeRouter is Auth, ICentrifugeRouter {
    using CastLib for address;

    IEscrow public immutable escrow;
    IGateway public immutable gateway;
    IPoolManager public immutable poolManager;

    address constant UNSET_INITIATOR = address(1);
    address internal _initiator = UNSET_INITIATOR;

    /// @inheritdoc ICentrifugeRouter
    mapping(address controller => mapping(address vault => bool)) public opened;

    /// @inheritdoc ICentrifugeRouter
    mapping(address controller => mapping(address vault => uint256 amount)) public lockedRequests;

    constructor(address escrow_, address gateway_, address poolManager_) {
        escrow = IEscrow(escrow_);
        gateway = IGateway(gateway_);
        poolManager = IPoolManager(poolManager_);

        wards[msg.sender] = 1;
        emit Rely(msg.sender);
    }

    modifier protected() {
        if (_initiator == UNSET_INITIATOR) {
            // Single call re-entrancy lock
            _initiator = msg.sender;
            _;
            _initiator = UNSET_INITIATOR;
        } else {
            // Multicall re-entrancy lock
            require(msg.sender == _initiator, "CentrifugeRouter/unauthorized-sender");
            _;
        }
    }

    // --- Administration ---
    /// @inheritdoc ICentrifugeRouter
    function recoverTokens(address token, address to, uint256 amount) external auth {
        SafeTransferLib.safeTransfer(token, to, amount);
    }

    // --- Deposit ---
    /// @inheritdoc ICentrifugeRouter
    function requestDeposit(address vault, uint256 amount, address controller, address owner, uint256 topUpAmount)
        external
        payable
        protected
    {
        (address asset,) = poolManager.getVaultAsset(vault);
        if (owner == address(this)) {
            _approveMax(asset, vault);
        }

        _pay(topUpAmount);
        IERC7540Vault(vault).requestDeposit(amount, controller, owner);
    }

    /// @inheritdoc ICentrifugeRouter
    function lockDepositRequest(address vault, uint256 amount, address controller, address owner)
        public
        payable
        protected
    {
        require(owner == _initiator || owner == address(this), "CentrifugeRouter/invalid-owner");

        lockedRequests[controller][vault] += amount;
        (address asset,) = poolManager.getVaultAsset(vault);
        SafeTransferLib.safeTransferFrom(asset, owner, address(escrow), amount);

        emit LockDepositRequest(vault, controller, owner, _initiator, amount);
    }

    /// @inheritdoc ICentrifugeRouter
    function openLockDepositRequest(address vault, uint256 amount) external payable protected {
        open(vault);

        (address asset, bool isWrapper) = poolManager.getVaultAsset(vault);

        if (isWrapper) {
            wrap(asset, amount, address(this), _initiator);
            lockDepositRequest(vault, amount, _initiator, address(this));
        } else {
            lockDepositRequest(vault, amount, _initiator, _initiator);
        }
    }

    /// @inheritdoc ICentrifugeRouter
    function unlockDepositRequest(address vault, address receiver) external payable protected {
        uint256 lockedRequest = lockedRequests[_initiator][vault];
        require(lockedRequest > 0, "CentrifugeRouter/user-has-no-locked-balance");
        lockedRequests[_initiator][vault] = 0;

        (address asset,) = poolManager.getVaultAsset(vault);
        escrow.approveMax(asset, address(this));
        SafeTransferLib.safeTransferFrom(asset, address(escrow), receiver, lockedRequest);

        emit UnlockDepositRequest(vault, _initiator, receiver);
    }

    /// @inheritdoc ICentrifugeRouter
    function executeLockedDepositRequest(address vault, address controller, uint256 topUpAmount)
        external
        payable
        protected
    {
        uint256 lockedRequest = lockedRequests[controller][vault];
        require(lockedRequest > 0, "CentrifugeRouter/controller-has-no-balance");
        lockedRequests[controller][vault] = 0;

        (address asset,) = poolManager.getVaultAsset(vault);

        escrow.approveMax(asset, address(this));
        SafeTransferLib.safeTransferFrom(asset, address(escrow), address(this), lockedRequest);

        _pay(topUpAmount);
        _approveMax(asset, vault);
        IERC7540Vault(vault).requestDeposit(lockedRequest, controller, address(this));
        emit ExecuteLockedDepositRequest(vault, controller, _initiator);
    }

    /// @inheritdoc ICentrifugeRouter
    function claimDeposit(address vault, address receiver, address controller) external payable protected {
        require(
            controller == _initiator || (controller == receiver && opened[controller][vault] == true),
            "CentrifugeRouter/invalid-sender"
        );
        uint256 maxDeposit = IERC7540Vault(vault).maxDeposit(controller);
        IERC7540Vault(vault).deposit(maxDeposit, receiver, controller);
    }

    /// @inheritdoc ICentrifugeRouter
    function cancelDepositRequest(address vault, address controller, uint256 topUpAmount) external payable protected {
        validateController(vault, controller);
        _pay(topUpAmount);
        IERC7540Vault(vault).cancelDepositRequest(0, controller);
    }

    /// @inheritdoc ICentrifugeRouter
    function claimCancelDepositRequest(address vault, address receiver, address controller)
        external
        payable
        protected
    {
        require(
            controller == _initiator || (controller == receiver && opened[controller][vault] == true),
            "CentrifugeRouter/invalid-sender"
        );
        IERC7540Vault(vault).claimCancelDepositRequest(0, receiver, controller);
    }

    // --- Redeem ---
    /// @inheritdoc ICentrifugeRouter
    function requestRedeem(address vault, uint256 amount, address controller, address owner, uint256 topUpAmount)
        external
        payable
        protected
    {
        _pay(topUpAmount);
        IERC7540Vault(vault).requestRedeem(amount, controller, owner);
    }

    /// @inheritdoc ICentrifugeRouter
    function claimRedeem(address vault, address receiver, address controller) external payable protected {
        bool permissionlesslyClaiming =
            controller != _initiator && controller == receiver && opened[controller][vault] == true;

        require(controller == _initiator || permissionlesslyClaiming, "CentrifugeRouter/invalid-sender");
        uint256 maxRedeem = IERC7540Vault(vault).maxRedeem(controller);

        (address asset, bool isWrapper) = poolManager.getVaultAsset(vault);
        if (isWrapper && permissionlesslyClaiming) {
            // Auto-unwrap if permissionlesly claiming for another controller
            uint256 assets = IERC7540Vault(vault).redeem(maxRedeem, address(this), controller);
            unwrap(asset, assets, receiver);
        } else {
            IERC7540Vault(vault).redeem(maxRedeem, receiver, controller);
        }
    }

    /// @inheritdoc ICentrifugeRouter
    function cancelRedeemRequest(address vault, address controller, uint256 topUpAmount) external payable protected {
        validateController(vault, controller);
        _pay(topUpAmount);
        IERC7540Vault(vault).cancelRedeemRequest(0, controller);
    }

    /// @inheritdoc ICentrifugeRouter
    function claimCancelRedeemRequest(address vault, address receiver, address controller) external payable protected {
        require(
            controller == _initiator || (controller == receiver && opened[controller][vault] == true),
            "CentrifugeRouter/invalid-sender"
        );
        IERC7540Vault(vault).claimCancelRedeemRequest(0, receiver, controller);
    }

    // --- Transfer ---
    /// @inheritdoc ICentrifugeRouter
    function transferAssets(address asset, bytes32 recipient, uint128 amount, uint256 topUpAmount)
        public
        payable
        protected
    {
        SafeTransferLib.safeTransferFrom(asset, _initiator, address(this), amount);
        _approveMax(asset, address(poolManager));
        _pay(topUpAmount);
        poolManager.transferAssets(asset, recipient, amount);
    }

    /// @inheritdoc ICentrifugeRouter
    function transferAssets(address asset, address recipient, uint128 amount, uint256 topUpAmount)
        external
        payable
        protected
    {
        transferAssets(asset, recipient.toBytes32(), amount, topUpAmount);
    }

    /// @inheritdoc ICentrifugeRouter
    function transferTrancheTokens(
        address vault,
        Domain domain,
        uint64 chainId,
        bytes32 recipient,
        uint128 amount,
        uint256 topUpAmount
    ) public payable protected {
        SafeTransferLib.safeTransferFrom(IERC7540Vault(vault).share(), _initiator, address(this), amount);
        _approveMax(IERC7540Vault(vault).share(), address(poolManager));
        _pay(topUpAmount);
        IPoolManager(poolManager).transferTrancheTokens(
            IERC7540Vault(vault).poolId(), IERC7540Vault(vault).trancheId(), domain, chainId, recipient, amount
        );
    }

    /// @inheritdoc ICentrifugeRouter
    function transferTrancheTokens(
        address vault,
        Domain domain,
        uint64 chainId,
        address recipient,
        uint128 amount,
        uint256 topUpAmount
    ) external payable protected {
        transferTrancheTokens(vault, domain, chainId, recipient.toBytes32(), amount, topUpAmount);
    }

    // --- Manage permissionless claiming ---
    function open(address vault) public protected {
        opened[_initiator][vault] = true;
    }

    function close(address vault) external protected {
        opened[_initiator][vault] = false;
    }

    // --- ERC20 permits ---
    /// @inheritdoc ICentrifugeRouter
    function permit(address asset, address spender, uint256 assets, uint256 deadline, uint8 v, bytes32 r, bytes32 s)
        external
        payable
        protected
    {
        try IERC20Permit(asset).permit(_initiator, spender, assets, deadline, v, r, s) {} catch {}
    }

    // --- ERC20 wrapping ---
    function wrap(address wrapper, uint256 amount, address receiver, address owner) public payable protected {
        require(owner == _initiator || owner == address(this), "CentrifugeRouter/invalid-owner");
        address underlying = IERC20Wrapper(wrapper).underlying();

        amount = MathLib.min(amount, IERC20(underlying).balanceOf(owner));
        require(amount != 0, "CentrifugeRouter/zero-balance");
        SafeTransferLib.safeTransferFrom(underlying, owner, address(this), amount);

        _approveMax(underlying, wrapper);
        require(IERC20Wrapper(wrapper).depositFor(receiver, amount), "CentrifugeRouter/deposit-for-failed");
    }

    function unwrap(address wrapper, uint256 amount, address receiver) public payable protected {
        amount = MathLib.min(amount, IERC20(wrapper).balanceOf(address(this)));
        require(amount != 0, "CentrifugeRouter/zero-balance");

        require(IERC20Wrapper(wrapper).withdrawTo(receiver, amount), "CentrifugeRouter/withdraw-to-failed");
    }

    // --- Batching ---
    /// @inheritdoc ICentrifugeRouter
    function multicall(bytes[] memory data) external payable {
        require(_initiator == UNSET_INITIATOR, "CentrifugeRouter/already-initiated");

        _initiator = msg.sender;
        for (uint256 i; i < data.length; ++i) {
            (bool success, bytes memory returnData) = address(this).delegatecall(data[i]);
            if (!success) {
                uint256 length = returnData.length;
                require(length > 0, "CentrifugeRouter/call-failed");

                assembly ("memory-safe") {
                    revert(add(32, returnData), length)
                }
            }
        }
        _initiator = UNSET_INITIATOR;
    }

    // --- View Methods ---
    /// @inheritdoc ICentrifugeRouter
    function getVault(uint64 poolId, bytes16 trancheId, address asset) external view returns (address) {
        return IPoolManager(poolManager).getVault(poolId, trancheId, asset);
    }

    /// @inheritdoc ICentrifugeRouter
    function estimate(bytes calldata payload) external view returns (uint256 amount) {
        (, amount) = IGateway(gateway).estimate(payload);
    }

    // --- Helpers ---
    /// @dev Gives the max approval to `to` to spend the given `asset` if not already approved.
    /// @dev Assumes that `type(uint256).max` is large enough to never have to increase the allowance again.
    function _approveMax(address token, address spender) internal {
        if (IERC20(token).allowance(address(this), spender) == 0) {
            SafeTransferLib.safeApprove(token, spender, type(uint256).max);
        }
    }

    function _pay(uint256 amount) internal {
        require(amount <= address(this).balance, "CentrifugeRouter/insufficient-funds-to-topup");
        gateway.topUp{value: amount}();

    }

    function validateController(address vault, address controller) internal view {
        require(
            controller == msg.sender || IERC7540Vault(vault).isOperator(controller, msg.sender)
                || IInvestmentManager(poolManager.investmentManager()).isGlobalOperator(address(this), msg.sender),
            "CentrifugeRouter/invalid-controller"
        );
    }
}
