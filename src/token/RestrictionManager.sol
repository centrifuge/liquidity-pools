// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import {Auth} from "src/Auth.sol";
import {IERC20, IERC20Callback, HookData} from "src/interfaces/IERC20.sol";
import {IRoot} from "src/interfaces/IRoot.sol";
import {IRestrictionManager} from "src/interfaces/token/IRestrictionManager.sol";
import {MessagesLib} from "src/libraries/MessagesLib.sol";
import {BitmapLib} from "src/libraries/BitmapLib.sol";
import {BytesLib} from "src/libraries/BytesLib.sol";

interface RestrictionManagerLike {
    function updateMember(address user, uint64 validUntil) external;
    function restrictions(address user) external view returns (bool frozen, uint64 validUntil);
    function freeze(address user) external;
    function unfreeze(address user) external;
}

interface TrancheTokenLike is IERC20 {
    function hookDataOf(address user) external view returns (bytes16);
    function setHookData(address user, bytes16 hookData) external returns (uint256);
}

/// @title  Restriction Manager
/// @notice ERC1404 based contract that checks transfer restrictions.
contract RestrictionManager is Auth, IRestrictionManager, IERC20Callback {
    using BitmapLib for *;
    using BytesLib for bytes;

    string internal constant SUCCESS_MESSAGE = "RestrictionManager/transfer-allowed";
    string internal constant SOURCE_IS_FROZEN_MESSAGE = "RestrictionManager/source-is-frozen";
    string internal constant DESTINATION_IS_FROZEN_MESSAGE = "RestrictionManager/destination-is-frozen";
    string internal constant DESTINATION_NOT_A_MEMBER_RESTRICTION_MESSAGE =
        "RestrictionManager/destination-not-a-member";

    uint8 public constant FREEZE_BIT = 127;
    uint8 public constant MEMBER_BIT = 126;

    uint8 public constant SUCCESS_CODE = 0;
    uint8 public constant SOURCE_IS_FROZEN_CODE = 1;
    uint8 public constant DESTINATION_IS_FROZEN_CODE = 2;
    uint8 public constant DESTINATION_NOT_A_MEMBER_RESTRICTION_CODE = 3;

    IRoot public immutable root;
    TrancheTokenLike public immutable token;

    constructor(address root_, address token_) {
        root = IRoot(root_);
        token = TrancheTokenLike(token_);

        wards[msg.sender] = 1;
        emit Rely(msg.sender);
    }

    // --- Callback from tranche token ---
    function onERC20Transfer(address from, address to, uint256 value, HookData calldata hookData)
        public
        virtual
        auth
        returns (bytes4)
    {
        uint8 restrictionCode = detectTransferRestriction(from, to, value, hookData);
        require(restrictionCode == SUCCESS_CODE, messageForTransferRestriction(restrictionCode));
        return bytes4(keccak256("onERC20Transfer(address,address,uint256,(bytes16,bytes16))"));
    }

    function onERC20AuthTransfer(
        address, /* sender */
        address, /* from */
        address, /* to */
        uint256, /* value */
        HookData calldata /* hookData */
    ) public virtual auth returns (bytes4) {
        return bytes4(keccak256("onERC20AuthTransfer(address,address,address,uint256,(bytes16,bytes16))"));
    }

    // --- ERC1404 implementation ---
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

    function detectTransferRestriction(address from, address to, uint256 amount) public view returns (uint8) {
        HookData memory hookData = HookData(token.hookDataOf(from), token.hookDataOf(to));

        // TODO: refactor to use other detectTransferRestriction implementation
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

    /// @inheritdoc IRestrictionManager
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
    /// @inheritdoc IRestrictionManager
    function updateRestriction(bytes memory update) external auth {
        MessagesLib.RestrictionUpdate updateId = MessagesLib.restrictionUpdateType(update);

        if (updateId == MessagesLib.RestrictionUpdate.UpdateMember) {
            updateMember(update.toAddress(1), update.toUint64(33));
        } else if (updateId == MessagesLib.RestrictionUpdate.Freeze) {
            freeze(update.toAddress(1));
        } else if (updateId == MessagesLib.RestrictionUpdate.Unfreeze) {
            unfreeze(update.toAddress(1));
        } else {
            revert("RestrictionManager/invalid-update");
        }
    }

    /// @inheritdoc IRestrictionManager
    function freeze(address user) public auth {
        require(user != address(0), "RestrictionManager/cannot-freeze-zero-address");
        require(!root.endorsed(user), "RestrictionManager/endorsed-user-cannot-be-frozen");

        uint128 hookData = uint128(token.hookDataOf(user));
        token.setHookData(user, bytes16(hookData.setBit(FREEZE_BIT, true)));

        emit Freeze(user);
    }

    /// @inheritdoc IRestrictionManager
    function unfreeze(address user) public auth {
        uint128 hookData = uint128(token.hookDataOf(user));
        token.setHookData(user, bytes16(hookData.setBit(FREEZE_BIT, false)));

        emit Unfreeze(user);
    }

    /// @inheritdoc IRestrictionManager
    function isFrozen(address user) public view returns (bool) {
        return uint128(token.hookDataOf(user)).getBit(FREEZE_BIT);
    }

    // --- Managing members ---
    /// @inheritdoc IRestrictionManager
    function updateMember(address user, uint64 validUntil) public auth {
        require(block.timestamp <= validUntil, "RestrictionManager/invalid-valid-until");
        require(!root.endorsed(user), "RestrictionManager/endorsed-user-cannot-be-updated");
        _updateMember(user, validUntil);
    }

    function _updateMember(address user, uint64 validUntil) internal {
        uint128 hookData = validUntil.shiftLeft(64).setBit(FREEZE_BIT, isFrozen(user));
        token.setHookData(user, bytes16(hookData));

        emit UpdateMember(user, validUntil);
    }

    /// @inheritdoc IRestrictionManager
    function isMember(address user) public view returns (bool) {
        return abi.encodePacked(token.hookDataOf(user)).toUint64(0) < block.timestamp;
    }
}
