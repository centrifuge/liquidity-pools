// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import {ERC20} from "src/token/ERC20.sol";
import {IERC20Metadata, IERC20Callback} from "src/interfaces/IERC20.sol";
import {IERC7575Share} from "src/interfaces/IERC7575.sol";
import {ITrancheToken} from "src/interfaces/token/ITranche.sol";

interface TrancheTokenLike is IERC20Metadata {
    function mint(address user, uint256 value) external;
    function burn(address user, uint256 value) external;
    function file(bytes32 what, string memory data) external;
    function file(bytes32 what, address data) external;
    function file(bytes32 what, address data1, address data2) external;
    function file(bytes32 what, address data1, bool data2) external;
    function restrictionSet() external view returns (address);
    function checkTransferRestriction(address from, address to, uint256 value) external view returns (bool);
    function vault(address asset) external view returns (address);
}

interface RestrictionSetLike {
    function detectTransferRestriction(address from, address to, uint256 value) external view returns (uint8);
    function messageForTransferRestriction(uint8 restrictionCode) external view returns (string memory);
    function SUCCESS_CODE() external view returns (uint8);
}

/// @title  Tranche Token
/// @notice Extension of ERC20 + ERC1404 for tranche tokens, hat ensures
///         the transfer restrictions as defined in the RestrictionManager.
contract TrancheToken is ERC20, ITrancheToken, IERC7575Share {
    address public restrictionSet;

    /// @inheritdoc IERC7575Share
    mapping(address asset => address) public vault;

    constructor(uint8 decimals_) ERC20(decimals_) {}

    // --- Administration ---
    /// @inheritdoc ITrancheToken
    function file(bytes32 what, address data) external auth {
        if (what == "restrictionSet") restrictionSet = data;
        else revert("TrancheToken/file-unrecognized-param");
        emit File(what, data);
    }

    /// @inheritdoc ITrancheToken
    function file(bytes32 what, address data1, address data2) external auth {
        if (what == "vault") vault[data1] = data2;
        else revert("TrancheToken/file-unrecognized-param");
        emit File(what, data1, data2);
    }

    // --- ERC20 overrides with restrictions ---
    function transfer(address to, uint256 value) public override returns (bool success) {
        success = super.transfer(to, value);
        require(
            restrictionSet == address(0)
                || IERC20Callback(restrictionSet).onERC20Transfer(msg.sender, to, value)
                    == IERC20Callback.onERC20Transfer.selector,
            "TrancheToken/restrictions-failed"
        );
    }

    function transferFrom(address from, address to, uint256 value) public override returns (bool success) {
        success = super.transferFrom(from, to, value);
        require(
            restrictionSet == address(0)
                || IERC20Callback(restrictionSet).onERC20Transfer(from, to, value)
                    == IERC20Callback.onERC20Transfer.selector,
            "TrancheToken/restrictions-failed"
        );
    }

    function mint(address to, uint256 value) public override {
        super.mint(to, value);
        require(
            restrictionSet == address(0)
                || IERC20Callback(restrictionSet).onERC20Transfer(address(0), to, value)
                    == IERC20Callback.onERC20Transfer.selector,
            "TrancheToken/restrictions-failed"
        );
    }

    // --- ERC1404 implementation ---
    /// @inheritdoc ITrancheToken
    function detectTransferRestriction(address from, address to, uint256 value) public view returns (uint8) {
        return RestrictionSetLike(restrictionSet).detectTransferRestriction(from, to, value);
    }

    /// @inheritdoc ITrancheToken
    function checkTransferRestriction(address from, address to, uint256 value) public view returns (bool) {
        return RestrictionSetLike(restrictionSet).detectTransferRestriction(from, to, value) == SUCCESS_CODE();
    }

    /// @inheritdoc ITrancheToken
    function messageForTransferRestriction(uint8 restrictionCode) public view returns (string memory) {
        return RestrictionSetLike(restrictionSet).messageForTransferRestriction(restrictionCode);
    }

    /// @inheritdoc ITrancheToken
    function SUCCESS_CODE() public view returns (uint8) {
        return RestrictionSetLike(restrictionSet).SUCCESS_CODE();
    }
}
