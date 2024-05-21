// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import {Auth} from "src/Auth.sol";
import {IERC20, IERC20Callback} from "src/interfaces/IERC20.sol";
import {IRestrictionManager} from "src/interfaces/token/IRestrictionManager.sol";

interface RestrictionManagerLike {
    function updateMember(address user, uint64 validUntil) external;
    function restrictions(address user) external view returns (bool frozen, uint64 validUntil);
    function freeze(address user) external;
    function unfreeze(address user) external;
}

/// @title  Restriction Manager
/// @notice ERC1404 based contract that checks transfer restrictions.
contract RestrictionManager is Auth, IRestrictionManager, IERC20Callback {
    string internal constant SUCCESS_MESSAGE = "RestrictionManager/transfer-allowed";
    string internal constant SOURCE_IS_FROZEN_MESSAGE = "RestrictionManager/source-is-frozen";
    string internal constant DESTINATION_IS_FROZEN_MESSAGE = "RestrictionManager/destination-is-frozen";
    string internal constant DESTINATION_NOT_A_MEMBER_RESTRICTION_MESSAGE =
        "RestrictionManager/destination-not-a-member";

    uint8 public constant SUCCESS_CODE = 0;
    uint8 public constant SOURCE_IS_FROZEN_CODE = 1;
    uint8 public constant DESTINATION_IS_FROZEN_CODE = 2;
    uint8 public constant DESTINATION_NOT_A_MEMBER_RESTRICTION_CODE = 3;

    IERC20 public immutable token;

    mapping(address => Restrictions) public restrictions;

    constructor(address token_) {
        token = IERC20(token_);

        wards[msg.sender] = 1;
        emit Rely(msg.sender);
    }

    // --- Callback from tranche token ---
    function onERC20Transfer(address from, address to, uint256 value) public virtual auth returns (bytes4) {
        uint8 restrictionCode = detectTransferRestriction(from, to, value);
        require(restrictionCode == SUCCESS_CODE, messageForTransferRestriction(restrictionCode));
        return bytes4(keccak256("onERC20Transfer(address,address,uint256)"));
    }

    function onERC20AuthTransfer(address sender, address from, address to, uint256 value)
        public
        virtual
        auth
        returns (bytes4)
    {
        uint8 restrictionCode = detectTransferRestriction(from, to, value);
        require(restrictionCode == SUCCESS_CODE, messageForTransferRestriction(restrictionCode));
        return bytes4(keccak256("onERC20AuthTransfer(address,address,address,uint256)"));
    }

    // --- ERC1404 implementation ---
    /// @inheritdoc IRestrictionManager
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
        _setBalance(user, balances[user].setBit(FREEZE_BIT, true));
        emit Freeze(user);
    }

    /// @inheritdoc IRestrictionManager
    function unfreeze(address user) public auth {
        _setBalance(user, balances[user].setBit(FREEZE_BIT, false));
        emit Unfreeze(user);
    }

    /// @inheritdoc IRestrictionManager
    function isFrozen(address user) public view returns (bool) {
        return balances[user].getBit(FREEZE_BIT);
    }

    // --- Managing members ---
    /// @inheritdoc IRestrictionManager
    function updateMember(address user, uint64 validUntil) public auth {
        require(block.timestamp <= validUntil, "TrancheToken01/invalid-valid-until");
        require(user != address(escrow), "TrancheToken01/escrow-member-cannot-be-updated");
        _updateMember(user, validUntil);
    }

    function _updateMember(address user, uint64 validUntil) internal {
        restrictions[user].validUntil = validUntil;
        _setBalance(user, balances[user].setBit(MEMBER_BIT, true));
        emit UpdateMember(user, validUntil);
    }

    /// @inheritdoc IRestrictionManager
    function setInvalidMember(address user) public {
        require(block.timestamp > restrictions[user].validUntil, "TrancheToken01/not-invalid-member");
        _setBalance(user, balances[user].setBit(MEMBER_BIT, false));
    }

    /// @inheritdoc IRestrictionManager
    function isMember(address user) public view returns (bool) {
        return balances[user].getBit(MEMBER_BIT);
    }

    // --- Fail-safe ---
    function authTransferFrom(address sender, address from, address to, uint256 value) public auth returns (bool) {
        return _transferFrom(sender, from, to, value);
    }
}
