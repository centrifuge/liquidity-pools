// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import {Auth} from "./../util/Auth.sol";
import {IERC20} from "../interfaces/IERC20.sol";

interface MemberlistLike {
    function updateMember(address user, uint256 validUntil) external;
    function members(address user) external view returns (uint256);
    function hasMember(address user) external view returns (bool);
}

/// @title  Restriction Manager
/// @notice ERC1404 based contract that checks transfer restrictions.
contract RestrictionManager is Auth {
    string internal constant SUCCESS_MESSAGE = "RestrictionManager/transfer-allowed";
    string internal constant SOURCE_IS_FROZEN_MESSAGE = "RestrictionManager/source-is-frozen";
    string internal constant DESTINATION_NOT_A_MEMBER_RESTRICTION_MESSAGE =
        "RestrictionManager/destination-not-a-member";
    string internal constant MINIMUM_BALANCE_NOT_REACHED_MESSAGE = "RestrictionManager/minimum-balance-not-reached";

    uint8 public constant SUCCESS_CODE = 0;
    uint8 public constant SOURCE_IS_FROZEN_CODE = 1;
    uint8 public constant DESTINATION_NOT_A_MEMBER_RESTRICTION_CODE = 2;
    uint8 public constant MINIMUM_BALANCE_NOT_REACHED_CODE = 3;

    IERC20 public immutable token;

    /// @dev Frozen accounts that tokens cannot be transferred from
    mapping(address => uint256) public frozen;

    /// @dev Member accounts that tokens can be transferred to
    mapping(address => uint256) public members;

    /// @dev Minimum balance that a destination needs to hold
    uint256 public minimumBalance;

    // --- Events ---
    event UpdateMember(address indexed user, uint256 validUntil);
    event Freeze(address indexed user);
    event Unfreeze(address indexed user);
    event UpdateMinimumBalance(uint256 indexed minimumBalance);

    constructor(address token_) {
        token = IERC20(token_);

        wards[msg.sender] = 1;
        emit Rely(msg.sender);
    }

    // --- ERC1404 implementation ---
    function detectTransferRestriction(address from, address to, uint256 value) public view returns (uint8) {
        if (frozen[from] == 1) {
            return SOURCE_IS_FROZEN_CODE;
        }

        if (!hasMember(to)) {
            return DESTINATION_NOT_A_MEMBER_RESTRICTION_CODE;
        }

        if (token.balanceOf(to) + value < minimumBalance) {
            return MINIMUM_BALANCE_NOT_REACHED_CODE;
        }

        return SUCCESS_CODE;
    }

    function messageForTransferRestriction(uint8 restrictionCode) public pure returns (string memory) {
        if (restrictionCode == SOURCE_IS_FROZEN_CODE) {
            return SOURCE_IS_FROZEN_MESSAGE;
        }

        if (restrictionCode == DESTINATION_NOT_A_MEMBER_RESTRICTION_CODE) {
            return DESTINATION_NOT_A_MEMBER_RESTRICTION_MESSAGE;
        }

        if (restrictionCode == MINIMUM_BALANCE_NOT_REACHED_CODE) {
            return MINIMUM_BALANCE_NOT_REACHED_MESSAGE;
        }

        return SUCCESS_MESSAGE;
    }

    // --- Handling freezes ---
    function freeze(address user) public auth {
        frozen[user] = 1;
        emit Freeze(user);
    }

    function unfreeze(address user) public auth {
        frozen[user] = 0;
        emit Unfreeze(user);
    }

    // --- Checking members ---
    function member(address user) public view {
        require((members[user] >= block.timestamp), "RestrictionManager/destination-not-a-member");
    }

    function hasMember(address user) public view returns (bool) {
        if (members[user] >= block.timestamp) {
            return true;
        }
        return false;
    }

    // --- Updating members ---
    function updateMember(address user, uint256 validUntil) public auth {
        require(block.timestamp <= validUntil, "RestrictionManager/invalid-valid-until");
        members[user] = validUntil;

        emit UpdateMember(user, validUntil);
    }

    function updateMembers(address[] memory users, uint256 validUntil) public auth {
        uint256 userLength = users.length;
        for (uint256 i = 0; i < userLength; i++) {
            updateMember(users[i], validUntil);
        }
    }

    // --- Managing min balance ---
    /// @dev If the minimum balance is increased, this will not impact existing
    ///      token balances, only future transfers.
    function updateMinimumBalance(uint256 newMinimumBalance) public auth {
        minimumBalance = newMinimumBalance;
        emit UpdateMinimumBalance(newMinimumBalance);
    }
}
