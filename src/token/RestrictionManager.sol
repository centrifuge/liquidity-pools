// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import {Auth} from "src/Auth.sol";
import {IERC20, IERC20Callback, HookData} from "src/interfaces/IERC20.sol";
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
    function hookDataOf(address user) external view returns (uint128);
    function setHookData(address user, uint128 hookData) external returns (uint256);
}

/// @title  Restriction Manager
/// @notice ERC1404 based contract that checks transfer restrictions.
contract RestrictionManager is Auth, IRestrictionManager, IERC20Callback {
    using BitmapLib for uint128;
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

    address public immutable escrow;
    TrancheTokenLike public immutable token;

    constructor(address token_, address escrow_) {
        token = TrancheTokenLike(token_);
        escrow = escrow_;
        _updateMember(escrow_, type(uint64).max);

        wards[msg.sender] = 1;
        emit Rely(msg.sender);
    }

    // --- Callback from tranche token ---
    function onERC20Transfer(address from, address to, uint256 value, HookData calldata hookData)
        public
        virtual
        auth
        returns (HookData calldata)
    {
        uint8 restrictionCode = detectTransferRestriction(from, to, value, hookData);
        require(restrictionCode == SUCCESS_CODE, messageForTransferRestriction(restrictionCode));
        return hookData;
    }

    function onERC20AuthTransfer(address sender, address from, address to, uint256 value, HookData calldata hookData)
        public
        virtual
        auth
        returns (HookData calldata)
    {
        uint8 restrictionCode = detectTransferRestriction(from, to, value, hookData);
        require(restrictionCode == SUCCESS_CODE, messageForTransferRestriction(restrictionCode));
        return hookData;
    }

    // --- ERC1404 implementation ---
    function detectTransferRestriction(address from, address to, uint256, /* value */ HookData calldata hookData)
        public
        view
        returns (uint8)
    {
        if (hookData.from.getBit(FREEZE_BIT) == true) {
            return SOURCE_IS_FROZEN_CODE;
        }

        if (hookData.to.getBit(FREEZE_BIT) == true) {
            return DESTINATION_IS_FROZEN_CODE;
        }

        // if (toRestrictions.validUntil < block.timestamp) {
        //     return DESTINATION_NOT_A_MEMBER_RESTRICTION_CODE;
        // }

        return SUCCESS_CODE;
    }

    function detectTransferRestriction(address from, address to, uint256) public view returns (uint8) {
        HookData memory hookData = HookData(token.hookDataOf(from), token.hookDataOf(to));
        // TODO: refactor
        if (hookData.from.getBit(FREEZE_BIT) == true) {
            return SOURCE_IS_FROZEN_CODE;
        }

        if (hookData.to.getBit(FREEZE_BIT) == true) {
            return DESTINATION_IS_FROZEN_CODE;
        }


        if (hookData.to.getBit(MEMBER_BIT) == false) {
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
        require(user != address(0), "TrancheToken01/cannot-freeze-zero-address");
        require(user != address(escrow), "TrancheToken01/cannot-freeze-escrow");

        uint128 hookData = token.hookDataOf(user);
        token.setHookData(user, hookData.setBit(FREEZE_BIT, true));

        emit Freeze(user);
    }

    /// @inheritdoc IRestrictionManager
    function unfreeze(address user) public auth {
        uint128 hookData = token.hookDataOf(user);
        token.setHookData(user, hookData.setBit(FREEZE_BIT, false));

        emit Unfreeze(user);
    }

    /// @inheritdoc IRestrictionManager
    function isFrozen(address user) public view returns (bool) {
        return token.hookDataOf(user).getBit(FREEZE_BIT);
    }

    // --- Managing members ---
    /// @inheritdoc IRestrictionManager
    function updateMember(address user, uint64 validUntil) public auth {
        require(block.timestamp <= validUntil, "TrancheToken01/invalid-valid-until");
        require(user != address(escrow), "TrancheToken01/escrow-member-cannot-be-updated");
        _updateMember(user, validUntil);
    }

    function _updateMember(address user, uint64 validUntil) internal {
        // TODO
        uint128 hookData = token.hookDataOf(user);
        token.setHookData(user, hookData.setBit(MEMBER_BIT, true));
        
        emit UpdateMember(user, validUntil);
    }

    /// @inheritdoc IRestrictionManager
    function isMember(address user) public view returns (bool) {
        // TODO
        return true;
    }
}
