// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import {Auth} from "src/Auth.sol";
import {IERC20} from "src/interfaces/IERC20.sol";
import {IRoot} from "src/interfaces/IRoot.sol";
import {ITranche} from "src/interfaces/token/ITranche.sol";
import {IHook, HookData, SUCCESS_CODE, SUCCESS_MESSAGE} from "src/interfaces/token/IHook.sol";
import {MessagesLib} from "src/libraries/MessagesLib.sol";
import {BitmapLib} from "src/libraries/BitmapLib.sol";
import {BytesLib} from "src/libraries/BytesLib.sol";
import {IERC165} from "src/interfaces/IERC7575.sol";
import "src/interfaces/token/IRestrictionManager.sol";

/// @title  Restriction Manager
/// @notice Hook implementation that:
///         * Requires adding accounts to the memberlist before they can receive tokens
///         * Supports freezing accounts which blocks transfers both to and from them
///         * Allows authTransferFrom calls
///
/// @dev    The first 8 bytes (uint64) of hookData is used for the memberlist valid until date,
///         the last bit is used to denote whether the account is frozen.
contract RestrictionManager is Auth, IRestrictionManager, IHook {
    using BitmapLib for *;
    using BytesLib for bytes;

    uint8 public constant FREEZE_BIT = 128 - 1;

    IRoot public immutable root;

    constructor(address root_) {
        root = IRoot(root_);

        wards[msg.sender] = 1;
        emit Rely(msg.sender);
    }

    // --- Callback from tranche token ---
    /// @inheritdoc IHook
    function onERC20Transfer(address from, address to, uint256 value, HookData calldata hookData)
        external
        virtual
        returns (bytes4)
    {
        uint8 restrictionCode = detectTransferRestriction(from, to, value, hookData);
        require(restrictionCode == SUCCESS_CODE, messageForTransferRestriction(restrictionCode));
        return bytes4(keccak256("onERC20Transfer(address,address,uint256,(bytes16,bytes16))"));
    }

    /// @inheritdoc IHook
    function onERC20AuthTransfer(
        address, /* sender */
        address, /* from */
        address, /* to */
        uint256, /* value */
        HookData calldata /* hookData */
    ) external pure returns (bytes4) {
        return bytes4(keccak256("onERC20AuthTransfer(address,address,address,uint256,(bytes16,bytes16))"));
    }

    // --- ERC1404 implementation ---
    /// @inheritdoc IHook
    function detectTransferRestriction(address from, address to, uint256, /* value */ HookData calldata hookData)
        public
        view
        returns (uint8)
    {
        if (uint128(hookData.from).getBit(FREEZE_BIT) == true && !root.endorsed(from)) {
            return SOURCE_IS_FROZEN_CODE;
        }

        bool toIsEndorsed = root.endorsed(to);
        if (uint128(hookData.to).getBit(FREEZE_BIT) == true && !toIsEndorsed) {
            return DESTINATION_IS_FROZEN_CODE;
        }

        if (abi.encodePacked(hookData.to).toUint64(0) < block.timestamp && !toIsEndorsed) {
            return DESTINATION_NOT_A_MEMBER_RESTRICTION_CODE;
        }

        return SUCCESS_CODE;
    }

    /// @inheritdoc IHook
    function messageForTransferRestriction(uint8 restrictionCode) public pure returns (string memory) {
        if (restrictionCode == SOURCE_IS_FROZEN_CODE) {
            return SOURCE_IS_FROZEN_MESSAGE;
        }

        if (restrictionCode == DESTINATION_IS_FROZEN_CODE) {
            return DESTINATION_IS_FROZEN_MESSAGE;
        }

        if (restrictionCode == DESTINATION_NOT_A_MEMBER_RESTRICTION_CODE) {
            return DESTINATION_NOT_A_MEMBER_RESTRICTION_MESSAGE;
        }

        return SUCCESS_MESSAGE;
    }

    // --- Incoming message handling ---
    /// @inheritdoc IHook
    function updateRestriction(address token, bytes memory update) external auth {
        RestrictionUpdate updateId = RestrictionUpdate(update.toUint8(0));

        if (updateId == RestrictionUpdate.UpdateMember) updateMember(token, update.toAddress(1), update.toUint64(33));
        else if (updateId == RestrictionUpdate.Freeze) freeze(token, update.toAddress(1));
        else if (updateId == RestrictionUpdate.Unfreeze) unfreeze(token, update.toAddress(1));
        else revert("RestrictionManager/invalid-update");
    }

    /// @inheritdoc IRestrictionManager
    function freeze(address token, address user) public auth {
        require(user != address(0), "RestrictionManager/cannot-freeze-zero-address");
        require(!root.endorsed(user), "RestrictionManager/endorsed-user-cannot-be-frozen");

        uint128 hookData = uint128(ITranche(token).hookDataOf(user));
        ITranche(token).setHookData(user, bytes16(hookData.setBit(FREEZE_BIT, true)));

        emit Freeze(token, user);
    }

    /// @inheritdoc IRestrictionManager
    function unfreeze(address token, address user) public auth {
        uint128 hookData = uint128(ITranche(token).hookDataOf(user));
        ITranche(token).setHookData(user, bytes16(hookData.setBit(FREEZE_BIT, false)));

        emit Unfreeze(token, user);
    }

    /// @inheritdoc IRestrictionManager
    function isFrozen(address token, address user) public view returns (bool) {
        return uint128(ITranche(token).hookDataOf(user)).getBit(FREEZE_BIT);
    }

    // --- Managing members ---
    /// @inheritdoc IRestrictionManager
    function updateMember(address token, address user, uint64 validUntil) public auth {
        require(block.timestamp <= validUntil, "RestrictionManager/invalid-valid-until");
        require(!root.endorsed(user), "RestrictionManager/endorsed-user-cannot-be-updated");

        uint128 hookData = validUntil.shiftLeft(64).setBit(FREEZE_BIT, isFrozen(token, user));
        ITranche(token).setHookData(user, bytes16(hookData));

        emit UpdateMember(token, user, validUntil);
    }

    /// @inheritdoc IRestrictionManager
    function isMember(address token, address user) public view returns (bool) {
        return abi.encodePacked(ITranche(token).hookDataOf(user)).toUint64(0) >= block.timestamp;
    }

    // --- ERC165 support ---
    /// @inheritdoc IERC165
    function supportsInterface(bytes4 interfaceId) external pure override returns (bool) {
        return interfaceId == type(IHook).interfaceId || interfaceId == type(IERC165).interfaceId;
    }
}
