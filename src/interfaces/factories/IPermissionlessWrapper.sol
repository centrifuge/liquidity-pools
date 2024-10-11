// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.5.0;

interface IPermissionlessWrapperFactory {
    event DeployPermissionlessWrapper(address caller, address underlying, address wrapper);

    /// @notice TODO
    function newWrapper(bytes32 salt, address underlying, string memory name, string memory symbol)
        external
        returns (address);
}
