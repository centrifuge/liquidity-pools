// SPDX-License-Identifier: MIT
pragma solidity >=0.5.0;

import {IERC165} from "src/interfaces/IERC7575.sol";

struct HookData {
    bytes16 from;
    bytes16 to;
}

uint8 constant SUCCESS_CODE_ID = 0;
string constant SUCCESS_MESSAGE = "transfer-allowed";

uint8 constant ERROR_CODE_ID = 1;
string constant ERROR_MESSAGE = "transfer-blocked";

interface IHook is IERC165 {
    /// @notice TODO
    function onERC20Transfer(address from, address to, uint256 value, HookData calldata hookdata)
        external
        returns (bytes4);

    /// @notice TODO
    function onERC20AuthTransfer(address sender, address from, address to, uint256 value, HookData calldata hookdata)
        external
        returns (bytes4);

    /// @notice TODO
    function checkERC20Transfer(address from, address to, uint256, /* value */ HookData calldata hookData)
        external
        view
        returns (bool);

    /// @notice TODO
    function updateRestriction(address token, bytes memory update) external;
}
