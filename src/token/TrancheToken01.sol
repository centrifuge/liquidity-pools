// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import {ERC20} from "src/token/ERC20.sol";
import {IERC20Metadata, IERC20Callback} from "src/interfaces/IERC20.sol";
import {IERC7575Share} from "src/interfaces/IERC7575.sol";
import {ITrancheToken01} from "src/interfaces/token/ITrancheToken01.sol";
import {MessagesLib} from "src/libraries/MessagesLib.sol";
import {BytesLib} from "src/libraries/BytesLib.sol";

interface TrancheTokenLike is IERC20Metadata {
    function mint(address user, uint256 value) external;
    function burn(address user, uint256 value) external;
    function file(bytes32 what, string memory data) external;
    function file(bytes32 what, address data) external;
    function file(bytes32 what, address data1, address data2) external;
    function file(bytes32 what, address data1, bool data2) external;
    function checkTransferRestriction(address from, address to, uint256 value) external view returns (bool);
    function vault(address asset) external view returns (address);
    function updateRestriction(bytes memory message) external;
    function updateMember(address user, uint64 validUntil) external;
    function restrictions(address user) external view returns (bool frozen, uint64 validUntil);
    function freeze(address user) external;
    function unfreeze(address user) external;
}

/// @title  Tranche Token 01
/// @notice Extension of ERC20 + ERC1404 for tranche tokens, that ensures
///         the destination of any transfer is a valid member, and neither
///         the source nor destination are frozen.
contract TrancheToken01 is ERC20, ITrancheToken01, IERC7575Share {
    using BytesLib for bytes;

    string internal constant SUCCESS_MESSAGE = "TrancheToken01/transfer-allowed";
    string internal constant SOURCE_IS_FROZEN_MESSAGE = "TrancheToken01/source-is-frozen";
    string internal constant DESTINATION_IS_FROZEN_MESSAGE = "TrancheToken01/destination-is-frozen";
    string internal constant DESTINATION_NOT_A_MEMBER_RESTRICTION_MESSAGE = "TrancheToken01/destination-not-a-member";

    uint8 public constant SUCCESS_CODE = 0;
    uint8 public constant SOURCE_IS_FROZEN_CODE = 1;
    uint8 public constant DESTINATION_IS_FROZEN_CODE = 2;
    uint8 public constant DESTINATION_NOT_A_MEMBER_RESTRICTION_CODE = 3;

    address public immutable escrow;

    /// @inheritdoc IERC7575Share
    mapping(address asset => address) public vault;

    mapping(address => Restrictions) public restrictions;

    constructor(uint8 decimals_, address escrow_) ERC20(decimals_) {
        // Add escrow as valid member
        escrow = escrow_;
        restrictions[escrow_].validUntil = type(uint64).max;
        emit UpdateMember(escrow_, type(uint64).max);
    }

    // --- Administration ---
    /// @inheritdoc ITrancheToken01
    function file(bytes32 what, address data1, address data2) external auth {
        if (what == "vault") vault[data1] = data2;
        else revert("TrancheToken01/file-unrecognized-param");
        emit File(what, data1, data2);
    }

    // --- ERC20 overrides with restrictions ---
    function transfer(address to, uint256 value) public override returns (bool success) {
        require(checkTransferRestriction(msg.sender, to, value), "TrancheToken01/restrictions-failed");
        success = super.transfer(to, value);
    }

    function transferFrom(address from, address to, uint256 value) public override returns (bool success) {
        require(checkTransferRestriction(from, to, value), "TrancheToken01/restrictions-failed");
        success = super.transferFrom(from, to, value);
    }

    function mint(address to, uint256 value) public override {
        require(checkTransferRestriction(address(0), to, value), "TrancheToken01/restrictions-failed");
        super.mint(to, value);
    }

    // --- ERC1404 implementation ---
    /// @inheritdoc ITrancheToken01
    function checkTransferRestriction(address from, address to, uint256 value) public view returns (bool) {
        return detectTransferRestriction(from, to, value) == SUCCESS_CODE;
    }

    /// @inheritdoc ITrancheToken01
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

    /// @inheritdoc ITrancheToken01
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
    /// @inheritdoc ITrancheToken01
    function updateRestriction(bytes memory update) external auth {
        MessagesLib.RestrictionUpdate updateId = MessagesLib.restrictionUpdateType(update);

        if (updateId == MessagesLib.RestrictionUpdate.UpdateMember) {
            updateMember(update.toAddress(1), update.toUint64(33));
        } else if (updateId == MessagesLib.RestrictionUpdate.Freeze) {
            freeze(update.toAddress(1));
        } else if (updateId == MessagesLib.RestrictionUpdate.Unfreeze) {
            unfreeze(update.toAddress(1));
        } else {
            revert("TrancheToken01/invalid-update");
        }
    }

    // --- Handling freezes ---
    /// @inheritdoc ITrancheToken01
    function freeze(address user) public auth {
        require(user != address(0), "TrancheToken01/cannot-freeze-zero-address");
        require(user != address(escrow), "TrancheToken01/cannot-freeze-escrow");
        restrictions[user].frozen = true;
        emit Freeze(user);
    }

    /// @inheritdoc ITrancheToken01
    function unfreeze(address user) public auth {
        restrictions[user].frozen = false;
        emit Unfreeze(user);
    }

    // --- Managing members ---
    /// @inheritdoc ITrancheToken01
    function updateMember(address user, uint64 validUntil) public auth {
        require(block.timestamp <= validUntil, "TrancheToken01/invalid-valid-until");
        require(user != address(escrow), "TrancheToken01/escrow-member-cannot-be-updated");

        restrictions[user].validUntil = validUntil;
        emit UpdateMember(user, validUntil);
    }
}
