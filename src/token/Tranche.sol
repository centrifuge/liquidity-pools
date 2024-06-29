// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import {ERC20} from "src/token/ERC20.sol";
import {IERC20Metadata} from "src/interfaces/IERC20.sol";
import {IHook, HookData, SUCCESS_CODE as SUCCESS_CODE_ID} from "src/interfaces/token/IHook.sol";
import {IERC7575Share, IERC165} from "src/interfaces/IERC7575.sol";
import {ITrancheToken} from "src/interfaces/token/ITranche.sol";
import {BitmapLib} from "src/libraries/BitmapLib.sol";

interface TrancheTokenLike is IERC20Metadata {
    function mint(address user, uint256 value) external;
    function burn(address user, uint256 value) external;
    function file(bytes32 what, string memory data) external;
    function file(bytes32 what, address data) external;
    function updateVault(address asset, address vault) external;
    function file(bytes32 what, address data1, bool data2) external;
    function hook() external view returns (address);
    function checkTransferRestriction(address from, address to, uint256 value) external view returns (bool);
    function vault(address asset) external view returns (address);
}

interface IERC1404 {
    function detectTransferRestriction(address from, address to, uint256 value) external view returns (uint8);
    function messageForTransferRestriction(uint8 restrictionCode) external view returns (string memory);
    function SUCCESS_CODE() external view returns (uint8);
}

/// @title  Tranche Token
/// @notice Extension of ERC20 + ERC1404 for tranche tokens,
///         integrating an external hook optionally for ERC20 callbacks and ERC1404 checks.
///
/// @dev    The user balance is limited to uint128. This is safe because the decimals are limited to 18,
///         thus the max balance is 2^128-1 / 10**18 = 3.40 * 10**20. This is also enforced on mint.
///
///         The most significant 128 bits of the uint256 balance value are used
///         to store hook data (e.g. restrictions for users).
contract TrancheToken is ERC20, ITrancheToken, IERC7575Share, IERC1404 {
    using BitmapLib for *;

    uint8 internal constant MAX_DECIMALS = 18;

    address public hook;

    /// @inheritdoc IERC7575Share
    mapping(address asset => address) public vault;

    constructor(uint8 decimals_) ERC20(decimals_) {
        require(decimals_ <= MAX_DECIMALS, "ERC20/too-many-decimals");
    }

    modifier authOrHook() {
        require(wards[msg.sender] == 1 || msg.sender == hook, "Auth/not-authorized");
        _;
    }

    // --- Administration ---
    /// @inheritdoc ITrancheToken
    function file(bytes32 what, address data) external authOrHook {
        if (what == "hook") hook = data;
        else revert("TrancheToken/file-unrecognized-param");
        emit File(what, data);
    }

    /// @inheritdoc ITrancheToken
    function updateVault(address asset, address vault_) external auth {
        vault[asset] = vault_;
        emit VaultUpdate(asset, vault_);
    }

    // --- ERC20 overrides ---
    function balanceOf(address user) public view override returns (uint256) {
        return balances[user].getLSBits(128);
    }

    /// @inheritdoc ITrancheToken
    function hookDataOf(address user) public view returns (bytes16) {
        return bytes16(uint128(balances[user].getMSBits(128)));
    }

    /// @inheritdoc ITrancheToken
    function setHookData(address user, bytes16 hookData) public authOrHook {
        /// Balance values are [uint128(hookData) + uint128(balance)]
        _setBalance(user, uint128(hookData).concat(uint128(balanceOf(user))));
        emit SetHookData(user, hookData);
    }

    function transfer(address to, uint256 value) public override returns (bool success) {
        success = super.transfer(to, value);
        _onTransfer(msg.sender, to, value);
    }

    function transferFrom(address from, address to, uint256 value) public override returns (bool success) {
        success = super.transferFrom(from, to, value);
        _onTransfer(from, to, value);
    }

    /// @inheritdoc ITrancheToken
    function mint(address to, uint256 value) public override(ERC20, ITrancheToken) {
        super.mint(to, value);
        require(totalSupply <= type(uint128).max, "Tranche/exceeds-max-supply");
        _onTransfer(address(0), to, value);
    }

    /// @inheritdoc ITrancheToken
    function burn(address from, uint256 value) public override(ERC20, ITrancheToken) {
        super.burn(from, value);
    }

    function _onTransfer(address from, address to, uint256 value) internal {
        if (hook != address(0)) {
            require(
                IHook(hook).onERC20Transfer(from, to, value, HookData(hookDataOf(from), hookDataOf(to)))
                    == IHook.onERC20Transfer.selector,
                "TrancheToken/restrictions-failed"
            );
        }
    }

    /// @inheritdoc ITrancheToken
    function authTransferFrom(address sender, address from, address to, uint256 value)
        public
        auth
        returns (bool success)
    {
        success = _transferFrom(sender, from, to, value);
        if (hook != address(0)) {
            require(
                IHook(hook).onERC20AuthTransfer(sender, from, to, value, HookData(hookDataOf(from), hookDataOf(to)))
                    == IHook.onERC20AuthTransfer.selector,
                "TrancheToken/restrictions-failed"
            );
        }
    }

    // --- ERC1404 implementation ---
    /// @inheritdoc ITrancheToken
    function checkTransferRestriction(address from, address to, uint256 value) public view returns (bool) {
        if (hook == address(0)) return true;
        return detectTransferRestriction(from, to, value) == SUCCESS_CODE_ID;
    }

    /// @inheritdoc IERC1404
    function detectTransferRestriction(address from, address to, uint256 value) public view returns (uint8) {
        if (hook == address(0)) return SUCCESS_CODE_ID;
        return IHook(hook).detectTransferRestriction(from, to, value, HookData(hookDataOf(from), hookDataOf(to)));
    }

    /// @inheritdoc IERC1404
    function messageForTransferRestriction(uint8 restrictionCode) public view returns (string memory) {
        if (hook == address(0)) return "";
        return IHook(hook).messageForTransferRestriction(restrictionCode);
    }

    /// @inheritdoc IERC1404
    function SUCCESS_CODE() public view returns (uint8) {
        return SUCCESS_CODE_ID;
    }

    // --- ERC165 support ---
    /// @inheritdoc IERC165
    function supportsInterface(bytes4 interfaceId) external pure override returns (bool) {
        return interfaceId == type(IERC7575Share).interfaceId || interfaceId == type(IERC165).interfaceId;
    }
}
