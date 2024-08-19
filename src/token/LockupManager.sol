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
import {RestrictionUpdate, ILockupManager} from "src/interfaces/token/ILockupManager.sol";

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

    /// @dev Least significant bit
    uint8 public constant FREEZE_BIT = 0;

    address public immutable escrow;
    IRoot public immutable root;

    struct LockupConfig {
        uint64 referenceDate;
        uint16 lockupDays; // type(uint16).max / 365 = 179 years
    }

    struct LockupData {
        uint16 firstUnlock; // days since referenceDate
        uint16 lastUnlock; // days since referenceDate
        uint128 alreadyUnlocked;
    }

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
        require(checkERC20Transfer(from, to, value, hookData), "LockupManager/transfer-blocked");
        return IHook.onERC20Transfer.selector;
    }

    /// @inheritdoc IHook
    function onERC20AuthTransfer(
        address, /* sender */
        address, /* from */
        address, /* to */
        uint256, /* value */
        HookData calldata /* hookData */
    ) external pure returns (bytes4) {
        return IHook.onERC20AuthTransfer.selector;
    }

    // --- ERC1404 implementation ---
    /// @inheritdoc IHook
    function checkERC20Transfer(address from, address to, uint256 value, HookData calldata hookData)
        public
        view
        returns (bool)
    {
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

        // TODO:
        // if (to != escrow && !checkUnlocked(from, value)) { return false; }

        return true;
    }

    // --- Incoming message handling ---
    /// @inheritdoc IHook
    function updateRestriction(address token, bytes memory update) external auth {
        RestrictionUpdate updateId = RestrictionUpdate(update.toUint8(0));

        if (updateId == RestrictionUpdate.UpdateMember) updateMember(token, update.toAddress(1), update.toUint64(33));
        else if (updateId == RestrictionUpdate.Freeze) freeze(token, update.toAddress(1));
        else if (updateId == RestrictionUpdate.Unfreeze) unfreeze(token, update.toAddress(1));
        else if (updateId == RestrictionUpdate.SetLockupPeriod) setLockupPeriod(token, update.toUint16(1));
        else revert("LockupManager/invalid-update");
    }

    /// @inheritdoc ILockupManager
    function setLockupPeriod(address token, uint16 lockupDays) public auth {
        LockupConfig memory config = lockupConfig[token];

        if (config.referenceDate == 0) {
            // First time the lockup is setup
            config.referenceDate = _midnightUTC(block.timestamp);
        }

        // Can never be decreased because then we can assume new transfers will always be added to the end of
        // the linked list, which greatly simplifies the implementation and makes it more gas efficient.
        require(lockupDays >= config.lockupDays, "LockupManager/cannot-decrease-lockup");
        config.lockupDays = lockupDays;

        emit SetLockupPeriod(lockupDays);
    }

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
