// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import {Auth} from "src/Auth.sol";
import {IRoot} from "src/interfaces/IRoot.sol";
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

    IRoot public immutable root;
    IERC20 public immutable token;

    mapping(address => Restrictions) public restrictions;

    constructor(address root_, address token_) {
        root = IRoot(root_);
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

    // --- ERC1404 implementation ---
    /// @inheritdoc IRestrictionManager
    function detectTransferRestriction(address from, address to, uint256 /* value */ ) public view returns (uint8) {
        if (restrictions[from].frozen == true && !root.endorsed(from)) {
            return SOURCE_IS_FROZEN_CODE;
        }

        Restrictions memory toRestrictions = restrictions[to];
        bool toIsEndorsed = root.endorsed(to);
        if (toRestrictions.frozen == true && !toIsEndorsed) {
            return DESTINATION_IS_FROZEN_CODE;
        }

        if (toRestrictions.validUntil < block.timestamp && !toIsEndorsed) {
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

    // --- Handling freezes ---
    /// @inheritdoc IRestrictionManager
    function freeze(address user) public auth {
        require(user != address(0), "RestrictionManager/cannot-freeze-zero-address");
        restrictions[user].frozen = true;
        emit Freeze(user);
    }

    /// @inheritdoc IRestrictionManager
    function unfreeze(address user) public auth {
        restrictions[user].frozen = false;
        emit Unfreeze(user);
    }

    // --- Managing members ---
    /// @inheritdoc IRestrictionManager
    function updateMember(address user, uint64 validUntil) public auth {
        require(block.timestamp <= validUntil, "RestrictionManager/invalid-valid-until");
        restrictions[user].validUntil = validUntil;

        emit UpdateMember(user, validUntil);
    }

    // --- Misc ---
    /// @inheritdoc IRestrictionManager
    function afterTransfer(address, /* from */ address, /* to */ uint256 /* value */ ) public virtual auth {}

    /// @inheritdoc IRestrictionManager
    function afterMint(address, /* to */ uint256 /* value */ ) public virtual auth {}
}
