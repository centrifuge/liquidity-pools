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

    /// @dev Least significant bit
    uint8 public constant FREEZE_BIT = 0;

    address public immutable escrow;
    IRoot public immutable root;

    mapping(address token => LockupConfig) public lockupConfig;
    mapping(address token => mapping(address user => LockupData)) lockups;

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

        // TODO: check handling if lockup days is not set

        // If transferring to another user, this resets the lockup period. This ensures fungibility.
        _addTransfer(token, to, value.toUint128());

        // TODO: remove locks from transferred tokens of sender

        // Unlocked balance already checked so setting to infinite
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
            // If auth transferring to escrow, it's a redemption that requires unlocked tokens.
            _tryUnlock(token, from, value.toUint128());
        }

        return IHook.onERC20AuthTransfer.selector;
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

        if (from != address(0) && to != escrow && unlockedBalance < value) {
            // Tokens are being transferred (not minted from address(0)), not being redeemed (sent to the escrow),
            // and the unlocked balance is insufficient.
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
        // uint128 unlockedBalance = unlocked(msg.sender, from);
        return checkERC20Transfer(from, to, value, hookData, 0); // , unlockedBalance
    }

    // --- Incoming message handling ---
    /// @inheritdoc IHook
    function updateRestriction(address token, bytes memory update) external auth {
        RestrictionUpdate updateId = RestrictionUpdate(update.toUint8(0));

        if (updateId == RestrictionUpdate.UpdateMember) updateMember(token, update.toAddress(1), update.toUint64(33));
        else if (updateId == RestrictionUpdate.Freeze) freeze(token, update.toAddress(1));
        else if (updateId == RestrictionUpdate.Unfreeze) unfreeze(token, update.toAddress(1));
        else if (updateId == RestrictionUpdate.SetLockupPeriod) setLockupPeriod(token, update.toUint16(1));
        else if (updateId == RestrictionUpdate.ForceUnlock) forceUnlock(token, update.toAddress(1));
        else revert("LockupManager/invalid-update");
    }

    /// @inheritdoc ILockupManager
    function setLockupPeriod(address token, uint16 lockupDays) public auth {
        LockupConfig storage config = lockupConfig[token];

        if (config.referenceDate == 0) {
            // First time the lockup is setup
            // Removing 1 day ensures the diff after the first transfer is non-zero
            config.referenceDate = _midnightUTC(uint64(block.timestamp)) - 1 days;
        }

        // Can never be decreased because then we can assume new transfers will always be added to the end of
        // the linked list, which greatly simplifies the implementation and makes it more gas efficient.
        require(lockupDays >= config.lockupDays, "LockupManager/cannot-decrease-lockup");
        config.lockupDays = lockupDays;

        emit SetLockupPeriod(token, lockupDays);
    }

    function _tryUnlock(address token, address user, uint128 amount) internal {
        (uint128 unlockAmountFound, uint16 today) = _unlocked(token, user, uint64(block.timestamp));
        require(unlockAmountFound >= amount, "LockupManager/insufficient-unlocked-balance");

        LockupData storage lockup = lockups[token][user];
        lockup.first = today;
        lockup.unlocked = unlockAmountFound - amount;
    }

    function _addTransfer(address token, address user, uint128 amount) internal {
        LockupConfig memory config = lockupConfig[token];
        uint16 daysSinceReferenceDate =
            ((_midnightUTC(uint64(block.timestamp)) / (1 days)) - (config.referenceDate / (1 days))).toUint16();

        emit DebugLog(daysSinceReferenceDate);
        LockupData storage lockup = lockups[token][user];
        lockup.transfers[daysSinceReferenceDate].amount += amount;

        if (lockup.first == 0) {
            lockup.first = daysSinceReferenceDate;
            lockup.last = daysSinceReferenceDate;
        } else if (lockup.last != daysSinceReferenceDate) {
            // if its the same as the last one, we dont need to update any pointers
            lockup.transfers[lockup.last].next = daysSinceReferenceDate; // link as next to previous last
            lockup.last = daysSinceReferenceDate; // set as new last
        }
    }

    // TODO: add unlock(address token, address user, uint16 day) external {}

    /// @inheritdoc ILockupManager
    // TODO: add amount parameter?
    function forceUnlock(address token, address user) public auth {
        lockups[token][user].first = 0;
        lockups[token][user].last = 0;
        lockups[token][user].unlocked = ITranche(token).balanceOf(user).toUint128();
        // TODO: reset mapping (potentially unbounded?)
        emit ForceUnlock(token, user);
    }

    event DebugLog(uint256 val);

    function _unlocked(address token, address user, uint64 timestamp)
        internal
        view
        returns (uint128 amount, uint16 today)
    {
        LockupData storage lockup = lockups[token][user];

        LockupConfig memory config = lockupConfig[token];
        uint16 timestampDays = uint16((_midnightUTC(uint64(timestamp)) / (1 days)));
        uint16 unlockedUntil = uint16(timestampDays - (config.referenceDate / (1 days))) - config.lockupDays;

        today = lockup.first;
        amount = lockup.unlocked;
        while (today <= unlockedUntil && today != 0) {
            amount += lockup.transfers[today].amount;
            today = lockup.transfers[today].next;
        }
    }

    /// @inheritdoc ILockupManager
    function unlocked(address token, address user) public returns (uint128 amount) {
        (amount,) = _unlocked(token, user, uint64(block.timestamp));
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
