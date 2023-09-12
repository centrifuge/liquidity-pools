// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

/// @title  ERC1271 Context
/// @dev    Provides information about the current execution context, including the
///         sender of the transaction and its data. While these are generally available
///         via msg.sender and msg.data, they should not be accessed in such a direct
///         manner, since when dealing with meta-transactions the account sending and
///         paying for execution may not be the actual sender (as far as an application
///         is concerned).
/// @dev    Adapted from OpenZeppelin Contracts v4.4.1 (utils/Context.sol)
abstract contract Context {
    function _msgSender() internal view virtual returns (address) {
        return msg.sender;
    }
}
