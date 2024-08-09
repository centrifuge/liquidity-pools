// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.26;

import {Auth} from "src/Auth.sol";
import {IRoot} from "src/interfaces/IRoot.sol";
import {ITranche} from "src/interfaces/token/ITranche.sol";
import {IHook, HookData} from "src/interfaces/token/IHook.sol";
import {MessagesLib} from "src/libraries/MessagesLib.sol";
import {BitmapLib} from "src/libraries/BitmapLib.sol";
import {BytesLib} from "src/libraries/BytesLib.sol";
import {IERC165} from "src/interfaces/IERC7575.sol";
import {RestrictionUpdate, IFreezeManager} from "src/interfaces/token/IFreezeManager.sol";

/// @title  Freeze Manager
/// @notice Hook implementation that:
///         * Supports freezing accounts which blocks transfers both to and from them
///         * Allows authTransferFrom calls
///
/// @dev    The last bit of hookData is used to denote whether the account is frozen.
contract FreezeManager is Auth, IFreezeManager, IHook {
    using BitmapLib for *;
    using BytesLib for bytes;

    /// @dev Least significant bit
    uint8 public constant FREEZE_BIT = 0;

    IRoot public immutable root;

    constructor(address root_, address deployer) Auth(deployer) {
        root = IRoot(root_);
    }

    // --- Callback from tranche token ---
    /// @inheritdoc IHook
    function onERC20Transfer(address from, address to, uint256 value, HookData calldata hookData)
        external
        virtual
        returns (bytes4)
    {
        require(checkERC20Transfer(from, to, value, hookData), "FreezeManager/transfer-blocked");
        return IHook.onERC20Transfer.selector;
    }

    /// @inheritdoc IHook
    function onERC20AuthTransfer(
        address, /* sender */
        address, /* from */
        address, /* to */
        uint256, /* value */
        HookData calldata /* hookData */
    ) external pure returns (bytes4) {
        return IHook.onERC20AuthTransfer.selector;
    }

    // --- ERC1404 implementation ---
    /// @inheritdoc IHook
    function checkERC20Transfer(address from, address to, uint256, /* value */ HookData calldata hookData)
        public
        view
        returns (bool)
    {
        if (uint128(hookData.from).getBit(FREEZE_BIT) == true && !root.endorsed(from)) {
            // Source is frozen and not endorsed
            return false;
        }

        return true;
    }

    // --- Incoming message handling ---
    /// @inheritdoc IHook
    function updateRestriction(address token, bytes memory update) external auth {
        RestrictionUpdate updateId = RestrictionUpdate(update.toUint8(0));

        if (updateId == RestrictionUpdate.Freeze) freeze(token, update.toAddress(1));
        else if (updateId == RestrictionUpdate.Unfreeze) unfreeze(token, update.toAddress(1));
        else revert("FreezeManager/invalid-update");
    }

    /// @inheritdoc IFreezeManager
    function freeze(address token, address user) public auth {
        require(user != address(0), "FreezeManager/cannot-freeze-zero-address");
        require(!root.endorsed(user), "FreezeManager/endorsed-user-cannot-be-frozen");

        uint128 hookData = uint128(ITranche(token).hookDataOf(user));
        ITranche(token).setHookData(user, bytes16(hookData.setBit(FREEZE_BIT, true)));

        emit Freeze(token, user);
    }

    /// @inheritdoc IFreezeManager
    function unfreeze(address token, address user) public auth {
        uint128 hookData = uint128(ITranche(token).hookDataOf(user));
        ITranche(token).setHookData(user, bytes16(hookData.setBit(FREEZE_BIT, false)));

        emit Unfreeze(token, user);
    }

    /// @inheritdoc IFreezeManager
    function isFrozen(address token, address user) public view returns (bool) {
        return uint128(ITranche(token).hookDataOf(user)).getBit(FREEZE_BIT);
    }

    // --- ERC165 support ---
    /// @inheritdoc IERC165
    function supportsInterface(bytes4 interfaceId) external pure override returns (bool) {
        return interfaceId == type(IHook).interfaceId || interfaceId == type(IERC165).interfaceId;
    }
}
