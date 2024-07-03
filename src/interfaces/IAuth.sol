// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.5.0;

interface IAuth {
    event Rely(address indexed user);
    event Deny(address indexed user);

    /// @notice Make user a ward (give them admin access)
    function rely(address user) external;

    /// @notice Remove user as a ward (remove admin access)
    function deny(address user) external;
}
