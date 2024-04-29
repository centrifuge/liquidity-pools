// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import {ERC20} from "./ERC20.sol";
import {IERC20Metadata} from "../interfaces/IERC20.sol";
import {ITrancheToken} from "src/interfaces/token/ITranche.sol";

interface TrancheTokenLike is IERC20Metadata {
    function mint(address user, uint256 value) external;
    function burn(address user, uint256 value) external;
    function file(bytes32 what, string memory data) external;
    function file(bytes32 what, address data) external;
    function file(bytes32 what, address data1, address data2) external;
    function file(bytes32 what, address data1, bool data2) external;
    function restrictionManager() external view returns (address);
    function checkTransferRestriction(address from, address to, uint256 value) external view returns (bool);
    function vault(address asset) external view returns (address);
}

interface RestrictionManagerLike {
    function detectTransferRestriction(address from, address to, uint256 value) external view returns (uint8);
    function messageForTransferRestriction(uint8 restrictionCode) external view returns (string memory);
    function SUCCESS_CODE() external view returns (uint8);
    function afterTransfer(address from, address to, uint256 value) external;
    function afterMint(address to, uint256 value) external;
}

/// @title  Tranche Token
/// @notice Extension of ERC20 + ERC1404 for tranche tokens, hat ensures
///         the transfer restrictions as defined in the RestrictionManager.
contract TrancheToken is ERC20, ITrancheToken {
    RestrictionManagerLike public restrictionManager;

    /// @dev Look up vault by the asset (part of ERC7575)
    mapping(address asset => address) public vault;

    constructor(uint8 decimals_) ERC20(decimals_) {}

    modifier restricted(address from, address to, uint256 value) {
        uint8 restrictionCode = detectTransferRestriction(from, to, value);
        require(restrictionCode == SUCCESS_CODE(), messageForTransferRestriction(restrictionCode));
        _;
    }

    // --- Administration ---
    /// @inheritdoc ITrancheToken
    function file(bytes32 what, address data) external auth {
        if (what == "restrictionManager") restrictionManager = RestrictionManagerLike(data);
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
    function transfer(address to, uint256 value)
        public
        override
        restricted(msg.sender, to, value)
        returns (bool success)
    {
        success = super.transfer(to, value);
        if (success) restrictionManager.afterTransfer(msg.sender, to, value);
    }

    function transferFrom(address from, address to, uint256 value)
        public
        override
        restricted(from, to, value)
        returns (bool success)
    {
        success = super.transferFrom(from, to, value);
        if (success) restrictionManager.afterTransfer(from, to, value);
    }

    function mint(address to, uint256 value) public override restricted(msg.sender, to, value) {
        super.mint(to, value);
        restrictionManager.afterMint(to, value);
    }

    // --- ERC1404 implementation ---
    /// @inheritdoc ITrancheToken
    function detectTransferRestriction(address from, address to, uint256 value) public view returns (uint8) {
        return restrictionManager.detectTransferRestriction(from, to, value);
    }

    /// @inheritdoc ITrancheToken
    function checkTransferRestriction(address from, address to, uint256 value) public view returns (bool) {
        return restrictionManager.detectTransferRestriction(from, to, value) == SUCCESS_CODE();
    }

    /// @inheritdoc ITrancheToken
    function messageForTransferRestriction(uint8 restrictionCode) public view returns (string memory) {
        return restrictionManager.messageForTransferRestriction(restrictionCode);
    }

    /// @inheritdoc ITrancheToken
    function SUCCESS_CODE() public view returns (uint8) {
        return restrictionManager.SUCCESS_CODE();
    }
}
