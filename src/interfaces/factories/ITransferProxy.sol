// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.5.0;

interface ITransferProxy {
    /// @dev Anyone can transfer tokens.
    function transfer(address asset, uint128 amount) external;

    /// @dev The recoverer can receive tokens back. This is not permissionless as this could lead
    ///      to griefing issues, where tokens are recovered before being transferred out.
    function recover(address asset, uint128 amount) external;
}

interface ITransferProxyFactory {
    /// @dev Lookup proxy, where id = keccak256(destination + recoverer)
    function proxies(bytes32 id) external view returns (address proxy);

    /// @dev Deploy new transfer proxy
    function newTransferProxy(bytes32 destination, address recoverer) external returns (address);
}
