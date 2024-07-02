// SPDX-License-Identifier: MIT
pragma solidity >=0.5.0;

import {IERC165} from "src/interfaces/IERC7575.sol";

struct HookData {
    bytes16 from;
    bytes16 to;
}

uint8 constant SUCCESS_CODE = 0;
string constant SUCCESS_MESSAGE = "transfer-allowed";

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
    function detectTransferRestriction(address from, address to, uint256, /* value */ HookData calldata hookData)
        external
        view
        returns (uint8);

    /// @notice TODO
    function messageForTransferRestriction(uint8 restrictionCode) external view returns (string memory);

    /// @notice TODO
    function updateRestriction(address token, bytes memory update) external;
}
