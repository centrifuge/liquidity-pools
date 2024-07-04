// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.26;

import {Auth} from "src/Auth.sol";
import {MathLib} from "src/libraries/MathLib.sol";
import {SafeTransferLib} from "src/libraries/SafeTransferLib.sol";
import {IERC20, IERC20Permit, IERC20Wrapper} from "src/interfaces/IERC20.sol";
import {IERC7540Vault} from "src/interfaces/IERC7540.sol";
import {ICentrifugeRouter} from "src/interfaces/ICentrifugeRouter.sol";
import {IPoolManager} from "src/interfaces/IPoolManager.sol";
import {IEscrow} from "src/interfaces/IEscrow.sol";
import {IGateway} from "src/interfaces/gateway/IGateway.sol";

interface GatewayLike {
    function topUp() external payable;
    function estimate(bytes calldata payload) external returns (uint256[] memory tranches, uint256 total);
}

contract CentrifugeRouter is Auth, ICentrifugeRouter {
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
        require(topUpAmount <= address(this).balance, "CentrifugeRouter/insufficient-funds-to-topup");

        address asset = poolManager.getVaultAsset(vault);

        if (owner == address(this)) {
            _approveMax(asset, vault);
        }

        gateway.topUp{value: topUpAmount}();
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
        SafeTransferLib.safeTransferFrom(poolManager.getVaultAsset(vault), owner, address(escrow), amount);
        emit LockDepositRequest(vault, controller, owner, _initiator, amount);
    }

    /// @inheritdoc ICentrifugeRouter
    function openLockDepositRequest(address vault, uint256 amount) external payable protected {
        open(vault);
        lockDepositRequest(vault, amount, _initiator, _initiator);
    }

    /// @inheritdoc ICentrifugeRouter
    function unlockDepositRequest(address vault) external payable protected {
        uint256 lockedRequest = lockedRequests[_initiator][vault];
        require(lockedRequest > 0, "CentrifugeRouter/user-has-no-locked-balance");
        lockedRequests[_initiator][vault] = 0;

        address asset = poolManager.getVaultAsset(vault);

        escrow.approveMax(asset, address(this));
        SafeTransferLib.safeTransferFrom(asset, address(escrow), _initiator, lockedRequest);
        emit UnlockDepositRequest(vault, _initiator);
    }

    // TODO This should be also payable.
    /// @inheritdoc ICentrifugeRouter
    function executeLockedDepositRequest(address vault, address controller) external payable protected {
        uint256 lockedRequest = lockedRequests[controller][vault];
        require(lockedRequest > 0, "CentrifugeRouter/controller-has-no-balance");
        lockedRequests[controller][vault] = 0;

        address asset = poolManager.getVaultAsset(vault);

        escrow.approveMax(asset, address(this));
        SafeTransferLib.safeTransferFrom(asset, address(escrow), address(this), lockedRequest);

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

    // --- Redeem ---
    // TODO this should be payable
    /// @inheritdoc ICentrifugeRouter
    function requestRedeem(address vault, uint256 amount, address controller, address owner)
        external
        payable
        protected
    {
        IERC7540Vault(vault).requestRedeem(amount, controller, owner);
    }

    /// @inheritdoc ICentrifugeRouter
    function claimRedeem(address vault, address receiver, address controller) external payable protected {
        require(
            controller == _initiator || (controller == receiver && opened[controller][vault] == true),
            "CentrifugeRouter/invalid-sender"
        );
        uint256 maxRedeem = IERC7540Vault(vault).maxRedeem(controller);
        IERC7540Vault(vault).redeem(maxRedeem, receiver, controller);
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
    function wrap(address wrapper, uint256 amount) external payable protected {
        address underlying = IERC20Wrapper(wrapper).underlying();

        amount = MathLib.min(amount, IERC20(underlying).balanceOf(_initiator));
        require(amount != 0, "CentrifugeRouter/zero-balance");
        SafeTransferLib.safeTransferFrom(underlying, _initiator, address(this), amount);

        _approveMax(underlying, wrapper);
        require(IERC20Wrapper(wrapper).depositFor(address(this), amount), "CentrifugeRouter/deposit-for-failed");
    }

    function unwrap(address wrapper, uint256 amount, address receiver) external payable protected {
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
}
