// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import {Auth} from "src/Auth.sol";
import {IERC20, IERC20Callback} from "src/interfaces/IERC20.sol";
import {BytesLib} from "src/libraries/BytesLib.sol";
import {MessagesLib} from "src/libraries/MessagesLib.sol";
import {IRestrictionSet01} from "src/interfaces/token/IRestrictionSet01.sol";

interface RestrictionSetLike {
    function handle(bytes memory message) external;
    function updateMember(address user, uint64 validUntil) external;
    function restrictions(address user) external view returns (bool frozen, uint64 validUntil);
    function freeze(address user) external;
    function unfreeze(address user) external;
}

/// @title  Restriction Set 1
/// @notice ERC1404 based contract that checks transfer restrictions.
contract RestrictionSet01 is Auth, IRestrictionSet01, IERC20Callback {
    using BytesLib for bytes;

    string internal constant SUCCESS_MESSAGE = "RestrictionSet01/transfer-allowed";
    string internal constant SOURCE_IS_FROZEN_MESSAGE = "RestrictionSet01/source-is-frozen";
    string internal constant DESTINATION_IS_FROZEN_MESSAGE = "RestrictionSet01/destination-is-frozen";
    string internal constant DESTINATION_NOT_A_MEMBER_RESTRICTION_MESSAGE = "RestrictionSet01/destination-not-a-member";

    uint8 public constant SUCCESS_CODE = 0;
    uint8 public constant SOURCE_IS_FROZEN_CODE = 1;
    uint8 public constant DESTINATION_IS_FROZEN_CODE = 2;
    uint8 public constant DESTINATION_NOT_A_MEMBER_RESTRICTION_CODE = 3;

    IERC20 public immutable token;
    address public immutable escrow;

    mapping(address => Restrictions) public restrictions;

    constructor(address token_, address escrow_) {
        token = IERC20(token_);

        // Add escrow as valid member
        restrictions[escrow_].validUntil = type(uint64).max;
        emit UpdateMember(escrow_, type(uint64).max);
        escrow = escrow_;

        wards[msg.sender] = 1;
        emit Rely(msg.sender);
    }

    // --- Callback from tranche token ---
    function onERC20Transfer(address from, address to, uint256 value) public virtual auth returns (bytes4) {
        uint8 restrictionCode = detectTransferRestriction(from, to, value);
        require(restrictionCode == SUCCESS_CODE, messageForTransferRestriction(restrictionCode));
        return bytes4(keccak256("onERC20Transfer(address,address,uint256)"));
    }

    // --- ERC1404 implementation ---
    /// @inheritdoc IRestrictionSet01
    function detectTransferRestriction(address from, address to, uint256 /* value */ ) public view returns (uint8) {
        if (restrictions[from].frozen == true) {
            return SOURCE_IS_FROZEN_CODE;
        }

        Restrictions memory toRestrictions = restrictions[to];
        if (toRestrictions.frozen == true) {
            return DESTINATION_IS_FROZEN_CODE;
        }

        if (toRestrictions.validUntil < block.timestamp) {
            return DESTINATION_NOT_A_MEMBER_RESTRICTION_CODE;
        }

        return SUCCESS_CODE;
    }

    /// @inheritdoc IRestrictionSet01
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
    /// @inheritdoc IRestrictionSet01
    function handle(bytes memory update) external auth {
        MessagesLib.RestrictionUpdate updateId = MessagesLib.restrictionUpdateType(update);

        if (updateId == MessagesLib.RestrictionUpdate.UpdateMember) {
            updateMember(update.toAddress(1), update.toUint64(33));
        } else if (updateId == MessagesLib.RestrictionUpdate.Freeze) {
            freeze(update.toAddress(1));
        } else if (updateId == MessagesLib.RestrictionUpdate.Unfreeze) {
            unfreeze(update.toAddress(1));
        } else {
            revert("RestrictionSet01/invalid-update");
        }
    }

    // --- Handling freezes ---
    /// @inheritdoc IRestrictionSet01
    function freeze(address user) public auth {
        require(user != address(0), "RestrictionSet01/cannot-freeze-zero-address");
        require(user != address(escrow), "RestrictionSet01/cannot-freeze-escrow");
        restrictions[user].frozen = true;
        emit Freeze(user);
    }

    /// @inheritdoc IRestrictionSet01
    function unfreeze(address user) public auth {
        restrictions[user].frozen = false;
        emit Unfreeze(user);
    }

    // --- Managing members ---
    /// @inheritdoc IRestrictionSet01
    function updateMember(address user, uint64 validUntil) public auth {
        require(block.timestamp <= validUntil, "RestrictionSet01/invalid-valid-until");
        require(user != address(escrow), "RestrictionSet01/escrow-member-cannot-be-updated");

        restrictions[user].validUntil = validUntil;
        emit UpdateMember(user, validUntil);
    }
}
