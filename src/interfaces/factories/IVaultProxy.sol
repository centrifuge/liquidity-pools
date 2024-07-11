// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.5.0;

interface IVaultProxy {
    /// @dev Anyone can submit deposit request if there is USDC approval
    function requestDeposit() external payable;

    /// @dev Anyone can submit redeem request if there is share token approval
    function requestRedeem() external payable;
}

interface IVaultProxyFactory {
    event DeployVaultProxy(address indexed vault, address indexed user, address proxy);

    /// @dev Lookup proxy by keccak256(vault,user)
    function proxies(bytes32 id) external view returns (address proxy);

    /// @dev Deploy new vault proxy
    function newVaultProxy(address vault, address user) external returns (address);
}
