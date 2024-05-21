// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import {ERC20} from "src/token/ERC20.sol";
import {IERC20Metadata, IERC20Callback} from "src/interfaces/IERC20.sol";
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
/// @dev    The user balance is limited to uint128. This is safe because the decimals are limited
///         to 18, thus the max balance is 2^128-1 / 10**18 = 3.40e20.
///
///         The most significant 128 bits of the uint256 balance value are used
///         to store hook data (e.g. restrictions for users).
contract TrancheToken is ERC20, ITrancheToken, IERC7575Share {
    using BitmapLib for uint256;

    uint8 internal constant MAX_DECIMALS = 18;

    address public hook;

    /// @inheritdoc IERC7575Share
    mapping(address asset => address) public vault;

    // , address escrow_
    constructor(uint8 decimals_) ERC20(decimals_) {
        require(decimals_ <= MAX_DECIMALS, "ERC20/too-many-decimals");

        // escrow = escrow_;
        // _updateMember(escrow_, type(uint64).max);
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

    function _hookDataOf(address user) internal view returns (uint128) {
        return uint128(balances[user].getMSBits(128));
    }

    function setHookData(address user, bytes16 hookData) public authOrHook returns (uint256) {
        _setBalance(user, hookData.concat(balances[user]));
    }

    function transfer(address to, uint256 value) public override returns (bool success) {
        success = super.transfer(to, value);
        require(
            hook == address(0)
                || IERC20Callback(hook).onERC20Transfer(msg.sender, to, value, _hookDataOf(msg.sender), _hookDataOf(to))
                    == IERC20Callback.onERC20Transfer.selector,
            "TrancheToken/restrictions-failed"
        );
    }

    function transferFrom(address from, address to, uint256 value) public override returns (bool success) {
        success = super.transferFrom(from, to, value);
        require(
            hook == address(0)
                || IERC20Callback(hook).onERC20Transfer(from, to, value, _hookDataOf(from), _hookDataOf(to))
                    == IERC20Callback.onERC20Transfer.selector,
            "TrancheToken/restrictions-failed"
        );
    }

    function mint(address to, uint256 value) public override {
        super.mint(to, value);
        require(
            hook == address(0)
                || IERC20Callback(hook).onERC20Transfer(address(0), to, value, 0, _hookDataOf(to))
                    == IERC20Callback.onERC20Transfer.selector,
            "TrancheToken/restrictions-failed"
        );
    }

    function authTransferFrom(address sender, address from, address to, uint256 value)
        public
        auth
        returns (bool success)
    {
        success = _transferFrom(sender, from, to, value);
        require(
            hook == address(0)
                || IERC20Callback(hook).onERC20AuthTransfer(
                    sender, from, to, value, _hookDataOf(sender), _hookDataOf(from), _hookDataOf(to)
                ) == IERC20Callback.onERC20Transfer.selector,
            "TrancheToken/restrictions-failed"
        );
    }

    // --- ERC1404 implementation ---
    /// @inheritdoc ITrancheToken
    function detectTransferRestriction(address from, address to, uint256 value) public view returns (uint8) {
        if (hook == address(0)) return 0;
        return IERC1404(hook).detectTransferRestriction(from, to, value);
    }

    /// @inheritdoc ITrancheToken
    function checkTransferRestriction(address from, address to, uint256 value) public view returns (bool) {
        if (hook == address(0)) return true;
        return IERC1404(hook).detectTransferRestriction(from, to, value) == SUCCESS_CODE();
    }

    /// @inheritdoc ITrancheToken
    function messageForTransferRestriction(uint8 restrictionCode) public view returns (string memory) {
        if (hook == address(0)) return "";
        return IERC1404(hook).messageForTransferRestriction(restrictionCode);
    }

    /// @inheritdoc ITrancheToken
    function SUCCESS_CODE() public view returns (uint8) {
        if (hook == address(0)) return 0;
        return IERC1404(hook).SUCCESS_CODE();
    }

    // --- ERC165 support ---
    /// @inheritdoc IERC165
    function supportsInterface(bytes4 interfaceId) external pure override returns (bool) {
        return interfaceId == type(IERC7575Share).interfaceId || interfaceId == type(IERC165).interfaceId;
    }
}
