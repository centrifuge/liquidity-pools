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
import {IEscrow} from "src/interfaces/IEscrow.sol";
import {IGateway} from "src/interfaces/gateway/IGateway.sol";
import {TransientStorage} from "src/libraries/TransientStorage.sol";
import {IRecoverable} from "src/interfaces/IRoot.sol";

/// @title  CentrifugeRouter
/// @notice This is a helper contract, designed to be the entrypoint for EOAs.
///         It removes the need to know about all other contracts and simplifies the way to interact with the protocol.
///         It also adds the need to fully pay for each step of the transaction execution.
///         CentrifugeRouter allows to caller to execution multiple function into a single transaction by taking advantage of
///         the multicall functionality which batches message calls into a single one.
contract CentrifugeRouter is Auth, ICentrifugeRouter {
    using CastLib for address;
    using TransientStorage for bytes32;

    bytes32 public constant INITIATOR_SLOT = bytes32(uint256(keccak256("initiator")) - 1);

    IEscrow public immutable escrow;
    IGateway public immutable gateway;
    IPoolManager public immutable poolManager;

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
        address currentInitiator = _initiator();
        if (currentInitiator == address(0)) {
            // Single call re-entrancy lock
            INITIATOR_SLOT.tstore(msg.sender);
            _;
            INITIATOR_SLOT.tstore(0);
        } else {
            // Multicall re-entrancy lock
            require(msg.sender == currentInitiator, "CentrifugeRouter/unauthorized-sender");
            _;
        }
    }

    // --- Administration ---
    /// @inheritdoc IRecoverable
    function recoverTokens(address token, address to, uint256 amount) external auth {
        SafeTransferLib.safeTransfer(token, to, amount);
    }

    // --- Enable interactions with the vault ---
    function open(address vault) public protected {
        IERC7540Vault(vault).setEndorsedOperator(_initiator(), true);
    }

    function close(address vault) external protected {
        IERC7540Vault(vault).setEndorsedOperator(_initiator(), false);
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
        address initiator = _initiator();
        require(owner == initiator || owner == address(this), "CentrifugeRouter/invalid-owner");

        lockedRequests[controller][vault] += amount;
        (address asset,) = poolManager.getVaultAsset(vault);
        SafeTransferLib.safeTransferFrom(asset, owner, address(escrow), amount);

        emit LockDepositRequest(vault, controller, owner, initiator, amount);
    }

    /// @inheritdoc ICentrifugeRouter
    function openLockDepositRequest(address vault, uint256 amount) external payable protected {
        open(vault);

        address initiator = _initiator();
        (address asset, bool isWrapper) = poolManager.getVaultAsset(vault);

        if (isWrapper) {
            wrap(asset, amount, address(this), initiator);
            lockDepositRequest(vault, amount, initiator, address(this));
        } else {
            lockDepositRequest(vault, amount, initiator, initiator);
        }
    }

    /// @inheritdoc ICentrifugeRouter
    function unlockDepositRequest(address vault, address receiver) external payable protected {
        address initiator = _initiator();
        uint256 lockedRequest = lockedRequests[initiator][vault];
        require(lockedRequest > 0, "CentrifugeRouter/user-has-no-locked-balance");
        lockedRequests[initiator][vault] = 0;

        (address asset,) = poolManager.getVaultAsset(vault);
        escrow.approveMax(asset, address(this));
        SafeTransferLib.safeTransferFrom(asset, address(escrow), receiver, lockedRequest);

        emit UnlockDepositRequest(vault, initiator, receiver);
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
        emit ExecuteLockedDepositRequest(vault, controller, _initiator());
    }

    /// @inheritdoc ICentrifugeRouter
    function claimDeposit(address vault, address receiver, address controller) external payable protected {
        require(
            controller == _initiator()
                || (controller == receiver && IERC7540Vault(vault).isOperator(controller, address(this))),
            "CentrifugeRouter/invalid-sender"
        );
        uint256 maxMint = IERC7540Vault(vault).maxMint(controller);
        IERC7540Vault(vault).mint(maxMint, receiver, controller);
    }

    /// @inheritdoc ICentrifugeRouter
    function cancelDepositRequest(address vault, uint256 topUpAmount) external payable protected {
        _pay(topUpAmount);
        IERC7540Vault(vault).cancelDepositRequest(0, _initiator());
    }

    /// @inheritdoc ICentrifugeRouter
    function claimCancelDepositRequest(address vault, address receiver, address controller)
        external
        payable
        protected
    {
        require(
            controller == _initiator()
                || (controller == receiver && IERC7540Vault(vault).isOperator(controller, address(this))),
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
        address initiator = _initiator();
        bool permissionlesslyClaiming = controller != initiator && controller == receiver
            && IERC7540Vault(vault).isOperator(controller, address(this));

        require(controller == initiator || permissionlesslyClaiming, "CentrifugeRouter/invalid-sender");
        uint256 maxWithdraw = IERC7540Vault(vault).maxWithdraw(controller);

        (address asset, bool isWrapper) = poolManager.getVaultAsset(vault);
        if (isWrapper && permissionlesslyClaiming) {
            // Auto-unwrap if permissionlessly claiming for another controller
            IERC7540Vault(vault).withdraw(maxWithdraw, address(this), controller);
            unwrap(asset, maxWithdraw, receiver);
        } else {
            IERC7540Vault(vault).withdraw(maxWithdraw, receiver, controller);
        }
    }

    /// @inheritdoc ICentrifugeRouter
    function cancelRedeemRequest(address vault, uint256 topUpAmount) external payable protected {
        _pay(topUpAmount);
        IERC7540Vault(vault).cancelRedeemRequest(0, _initiator());
    }

    /// @inheritdoc ICentrifugeRouter
    function claimCancelRedeemRequest(address vault, address receiver, address controller) external payable protected {
        require(
            controller == _initiator()
                || (controller == receiver && IERC7540Vault(vault).isOperator(controller, address(this))),
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
        SafeTransferLib.safeTransferFrom(asset, _initiator(), address(this), amount);
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
        SafeTransferLib.safeTransferFrom(IERC7540Vault(vault).share(), _initiator(), address(this), amount);
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

    // --- ERC20 permits ---
    /// @inheritdoc ICentrifugeRouter
    function permit(address asset, address spender, uint256 assets, uint256 deadline, uint8 v, bytes32 r, bytes32 s)
        external
        payable
        protected
    {
        try IERC20Permit(asset).permit(_initiator(), spender, assets, deadline, v, r, s) {} catch {}
    }

    // --- ERC20 wrapping ---
    function wrap(address wrapper, uint256 amount, address receiver, address owner) public payable protected {
        require(owner == _initiator() || owner == address(this), "CentrifugeRouter/invalid-owner");
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
        require(INITIATOR_SLOT.tloadAddress() == address(0), "CentrifugeRouter/already-initiated");

        INITIATOR_SLOT.tstore(msg.sender);
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
        INITIATOR_SLOT.tstore(0);
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
    function _initiator() internal view returns (address) {
        return INITIATOR_SLOT.tloadAddress();
    }

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
}
