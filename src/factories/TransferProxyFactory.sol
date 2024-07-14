// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.26;

import {IPoolManager} from "src/interfaces/IPoolManager.sol";
import {ITransferProxy, ITransferProxyFactory} from "src/interfaces/factories/ITransferProxy.sol";

contract TransferProxy is ITransferProxy {
    IPoolManager public immutable poolManager;
    bytes32 public immutable destination;

    constructor(address poolManager_, bytes32 destination_) {
        poolManager = IPoolManager(poolManager_);
        destination = destination_;
    }

    /// @inheritdoc ITransferProxy
    function transfer(address asset, uint128 amount) external {
        poolManager.transferAssets(asset, destination, amount);
    }
}

interface TransferProxyFactoryLike {
    function newTransferProxy(address poolManager, bytes32 destination) external returns (address);
}

/// @title  Restricted Transfer Proxy Factory
/// @dev    Utility for deploying contracts that have a fixed destination for transfers
///         Users can send tokens to the TransferProxy, from a service that only supports
///         ERC20 transfers and not full contract calls.
contract TransferProxyFactory is ITransferProxyFactory {
    address public immutable poolManager;

    /// @inheritdoc ITransferProxyFactory
    mapping(bytes32 id => address proxy) public proxies;

    constructor(address poolManager_) {
        poolManager = poolManager_;
    }

    /// @inheritdoc ITransferProxyFactory
    function newTransferProxy(bytes32 destination) external returns (address) {
        require(proxies[destination] == address(0), "TransferProxyFactory/already-deployed");

        address proxy = address(new TransferProxy(poolManager, destination));
        proxies[destination] = proxy;

        emit DeployTransferProxy(destination, proxy);
        return proxy;
    }
}
