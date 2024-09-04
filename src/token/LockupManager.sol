// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.26;

import {Auth} from "src/Auth.sol";
import {IRoot} from "src/interfaces/IRoot.sol";
import {ITranche} from "src/interfaces/token/ITranche.sol";
import {IHook, HookData} from "src/interfaces/token/IHook.sol";
import {MessagesLib} from "src/libraries/MessagesLib.sol";
import {BitmapLib} from "src/libraries/BitmapLib.sol";
import {BytesLib} from "src/libraries/BytesLib.sol";
import {IERC165} from "src/interfaces/IERC7575.sol";
import {
    RestrictionUpdate,
    LockupConfig,
    Transfer,
    LockupData,
    ILockupManager
} from "src/interfaces/token/ILockupManager.sol";
import {MathLib} from "src/libraries/MathLib.sol";

/// @title  Lockup Manager
/// @notice Hook implementation that:
///         * Requires adding accounts to the memberlist before they can receive tokens
///         * Supports freezing accounts which blocks transfers both to and from them
///         * Allows authTransferFrom calls
///         * Supports setting up lockup periods for tranche tokens
///
/// @dev    The first 8 bytes (uint64) of hookData is used for the memberlist valid until date,
///         the last bit is used to denote whether the account is frozen.
contract LockupManager is Auth, ILockupManager, IHook {
    using BitmapLib for *;
    using BytesLib for bytes;
    using MathLib for uint64;
    using MathLib for uint256;

    uint256 internal constant SEC_PER_DAY = 60 * 60 * 24;

    /// @dev Least significant bit
    uint8 public constant FREEZE_BIT = 0;

    address public immutable escrow;
    IRoot public immutable root;

    mapping(address token => LockupConfig) internal _lockupConfig;
    mapping(address token => mapping(address user => LockupData)) internal _lockups;

    constructor(address root_, address escrow_, address deployer) Auth(deployer) {
        root = IRoot(root_);
        escrow = escrow_;
    }

    // --- Callback from tranche token ---
    /// @inheritdoc IHook
    function onERC20Transfer(address from, address to, uint256 value, HookData calldata hookData)
        external
        virtual
        returns (bytes4)
    {
        address token = msg.sender;

        if (from != address(0)) {
            // Reset lockups for source
            _transferFrom(token, from, value.toUint128());
        }

        // Add lock for destination
        _transferTo(token, to, value.toUint128());

        // Check memberlist and freeze status
        require(checkERC20Transfer(from, to, value, hookData, type(uint128).max), "LockupManager/transfer-blocked");

        return IHook.onERC20Transfer.selector;
    }

    /// @inheritdoc IHook
    function onERC20AuthTransfer(
        address, /* sender */
        address from,
        address to,
        uint256 value,
        HookData calldata /* hookData */
    ) external returns (bytes4) {
        address token = msg.sender;

        if (to == address(escrow)) {
            // If auth transferring to escrow, it's a redemption request that requires unlocked tokens.
            _requestRedeem(token, from, value.toUint128());
        } else {
            // If auth transferring somewhere else, consider it a normal ERC20 transfer wrt lockups
            _transferFrom(token, from, value.toUint128());
            _transferTo(token, to, value.toUint128());
        }

        return IHook.onERC20AuthTransfer.selector;
    }

    // --- Lockup logic ---
    function _requestRedeem(address token, address user, uint128 amount) internal {
        (uint128 unlockAmountFound, uint16 today) = _unlocked(token, user, uint64(block.timestamp));
        require(unlockAmountFound >= amount, "LockupManager/insufficient-unlocked-balance");

        LockupData storage lockup = _lockups[token][user];
        lockup.first = today;
        lockup.unlocked = unlockAmountFound - amount;
    }

    function _transferFrom(address token, address user, uint128 amount) internal {
        (uint128 unlockAmountFound, uint16 today) = _unlocked(token, user, uint64(block.timestamp));
        require(
            unlockAmountFound >= amount || !_lockupConfig[token].locksTransfers,
            "LockupManager/insufficient-unlocked-balance"
        );

        LockupData storage lockup = _lockups[token][user];
        lockup.first = today;
        if (unlockAmountFound > amount + lockup.transferred) {
            lockup.unlocked = unlockAmountFound - lockup.transferred - amount;
            lockup.transferred = 0;
        } else {
            // If unlocked balance is insufficient, store as transferred, and deduct on next unlock
            lockup.transferred += amount;
        }
    }

    function _transferTo(address token, address user, uint128 amount) internal {
        LockupConfig memory config = _lockupConfig[token];
        uint16 lockDays =
            ((_midnightUTC(uint64(block.timestamp)) / (1 days)) - (config.referenceDate / (1 days))).toUint16();

        LockupData storage lockup = _lockups[token][user];
        lockup.transfers[lockDays].amount += amount;

        if (lockup.first == 0) {
            // First lock being added
            lockup.first = lockDays;
            lockup.last = lockDays;
        } else if (lockup.last != lockDays) {
            // At least 1 lock already exists and it is not the same day as today
            lockup.transfers[lockup.last].next = lockDays;
            lockup.last = lockDays;

            // Unlock the first day if it has passed the lockup period.
            // This prevents griefing attacks where a user continually sends tokens (once per day) to user, to
            // increase the cost of claiming beyond the max gas limit. Now, each transfer past the lockup period
            // will trigger 1 unlock, thus limiting the max unlock count to the lockup period in days.
            if (config.lockupDays <= lockDays && lockup.first >= lockDays - config.lockupDays) {
                lockup.unlocked += lockup.transfers[lockup.first].amount;
                lockup.first = lockup.transfers[lockup.first].next;
            }
        }

        emit Lock(token, user, amount, uint64(block.timestamp + config.lockupDays * SEC_PER_DAY));
    }

    function _unlocked(address token, address user, uint64 timestamp)
        internal
        view
        returns (uint128 amount, uint16 today)
    {
        LockupData storage lockup = _lockups[token][user];

        LockupConfig memory config = _lockupConfig[token];
        uint16 timestampDays = uint16((_midnightUTC(uint64(timestamp)) / (1 days)));
        if (config.lockupDays > uint16(timestampDays - (config.referenceDate / (1 days)))) {
            return (0, timestampDays);
        }

        uint16 unlockedUntil = uint16(timestampDays - (config.referenceDate / (1 days))) - config.lockupDays;
        today = lockup.first;
        amount = lockup.unlocked;
        while (today <= unlockedUntil && today != 0) {
            amount += lockup.transfers[today].amount;
            today = lockup.transfers[today].next;
        }

        amount = amount > lockup.transferred ? amount - lockup.transferred : 0;
    }

    /// @inheritdoc ILockupManager
    function unlocked(address token, address user) external view returns (uint128 amount) {
        (amount,) = _unlocked(token, user, uint64(block.timestamp));
    }

    // --- ERC1404 implementation ---
    /// @inheritdoc ILockupManager
    function checkERC20Transfer(
        address from,
        address to,
        uint256 value,
        HookData calldata hookData,
        uint128 unlockedBalance
    ) public view returns (bool) {
        if (uint128(hookData.from).getBit(FREEZE_BIT) == true && !root.endorsed(from)) {
            // Source is frozen and not endorsed
            return false;
        }

        if (root.endorsed(to) || to == address(0)) {
            // Destination is endorsed and source was already checked, so the transfer is allowed
            return true;
        }

        uint128 toHookData = uint128(hookData.to);
        if (toHookData.getBit(FREEZE_BIT) == true) {
            // Destination is frozen
            return false;
        }

        if (toHookData >> 64 < block.timestamp) {
            // Destination is not a member
            return false;
        }

        if (to == escrow && unlockedBalance < value) {
            // Tokens are being being redeemed (sent to the escrow) and the unlocked balance is insufficient
            return false;
        }

        address token = msg.sender;
        if (from != address(0) && _lockupConfig[token].locksTransfers && unlockedBalance < value) {
            // Tokens are being being transferred, and the unlocked balance is insufficient
            return false;
        }

        return true;
    }

    /// @inheritdoc IHook
    /// @dev Assumes msg.sender is token
    function checkERC20Transfer(address from, address to, uint256 value, HookData calldata hookData)
        public
        view
        returns (bool)
    {
        (uint128 unlockedBalance,) = _unlocked(msg.sender, from, uint64(block.timestamp));
        return checkERC20Transfer(from, to, value, hookData, unlockedBalance);
    }

    // --- Incoming message handling ---
    /// @inheritdoc IHook
    function updateRestriction(address token, bytes memory update) external auth {
        RestrictionUpdate updateId = RestrictionUpdate(update.toUint8(0));

        if (updateId == RestrictionUpdate.UpdateMember) {
            updateMember(token, update.toAddress(1), update.toUint64(33));
        } else if (updateId == RestrictionUpdate.Freeze) {
            freeze(token, update.toAddress(1));
        } else if (updateId == RestrictionUpdate.Unfreeze) {
            unfreeze(token, update.toAddress(1));
        } else if (updateId == RestrictionUpdate.SetLockupPeriod) {
            setLockup(token, update.toUint16(1), update.toUint32(3), update.toBool(7));
        } else if (updateId == RestrictionUpdate.ForceUnlock) {
            forceUnlock(token, update.toAddress(1), update.toUint128(33));
        } else {
            revert("LockupManager/invalid-update");
        }
    }

    /// @inheritdoc ILockupManager
    function setLockup(address token, uint16 lockupDays, uint32 time, bool locksTransfers) public auth {
        LockupConfig storage config = _lockupConfig[token];

        if (config.referenceDate == 0) {
            // First time the lockup is setup
            // Removing 1 day ensures the diff after the first transfer is non-zero
            config.referenceDate = (_midnightUTC(uint64(block.timestamp)) - 1 days);
        }
        require(time <= SEC_PER_DAY, "LockupManager/invalid-time-of-day");
        config.time = time;

        config.lockupDays = lockupDays;
        config.locksTransfers = locksTransfers;

        emit SetLockup(token, lockupDays, time, locksTransfers);
    }

    /// @inheritdoc ILockupManager
    function forceUnlock(address token, address user, uint128 amount) public auth {
        LockupData storage lockup = _lockups[token][user];
        uint16 today = lockup.first;
        uint256 found = 0;
        while (found < amount && today != 0) {
            found += lockup.transfers[today].amount;
            today = lockup.transfers[today].next;
        }

        lockup.first = today;
        _lockups[token][user].unlocked += amount;

        emit ForceUnlock(token, user);
    }

    // --- Freezing ---
    /// @inheritdoc ILockupManager
    function freeze(address token, address user) public auth {
        require(user != address(0), "LockupManager/cannot-freeze-zero-address");
        require(!root.endorsed(user), "LockupManager/endorsed-user-cannot-be-frozen");

        uint128 hookData = uint128(ITranche(token).hookDataOf(user));
        ITranche(token).setHookData(user, bytes16(hookData.setBit(FREEZE_BIT, true)));

        emit Freeze(token, user);
    }

    /// @inheritdoc ILockupManager
    function unfreeze(address token, address user) public auth {
        uint128 hookData = uint128(ITranche(token).hookDataOf(user));
        ITranche(token).setHookData(user, bytes16(hookData.setBit(FREEZE_BIT, false)));

        emit Unfreeze(token, user);
    }

    /// @inheritdoc ILockupManager
    function isFrozen(address token, address user) public view returns (bool) {
        return uint128(ITranche(token).hookDataOf(user)).getBit(FREEZE_BIT);
    }

    // --- Managing members ---
    /// @inheritdoc ILockupManager
    function updateMember(address token, address user, uint64 validUntil) public auth {
        require(block.timestamp <= validUntil, "LockupManager/invalid-valid-until");
        require(!root.endorsed(user), "LockupManager/endorsed-user-cannot-be-updated");

        uint128 hookData = uint128(validUntil) << 64;
        hookData.setBit(FREEZE_BIT, isFrozen(token, user));
        ITranche(token).setHookData(user, bytes16(hookData));

        emit UpdateMember(token, user, validUntil);
    }

    /// @inheritdoc ILockupManager
    function isMember(address token, address user) external view returns (bool isValid, uint64 validUntil) {
        validUntil = abi.encodePacked(ITranche(token).hookDataOf(user)).toUint64(0);
        isValid = validUntil >= block.timestamp;
    }

    // --- ERC165 support ---
    /// @inheritdoc IERC165
    function supportsInterface(bytes4 interfaceId) external pure override returns (bool) {
        return interfaceId == type(IHook).interfaceId || interfaceId == type(IERC165).interfaceId;
    }

    // --- Helpers ---
    function _midnightUTC(uint64 timestamp) internal pure returns (uint64) {
        return (1 days) * (timestamp / (1 days));
    }
}
