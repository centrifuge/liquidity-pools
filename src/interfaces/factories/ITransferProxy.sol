// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.5.0;

interface ITransferProxy {
    /// @dev Anyone can transfer tokens.
    function transfer(address asset, uint128 amount) external;
}

interface ITransferProxyFactory {
    event DeployTransferProxy(bytes32 indexed destination, address proxy);

    /// @dev Lookup proxy by destination address
    function proxies(bytes32 destination) external view returns (address proxy);

    /// @dev Deploy new transfer proxy
    function newTransferProxy(bytes32 destination) external returns (address);
}
