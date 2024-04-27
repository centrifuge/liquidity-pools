// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import {SafeTransferLib} from "src/libraries/SafeTransferLib.sol";
import {IPoolManager} from "src/interfaces/IPoolManager.sol";
import {ITransferProxy, ITransferProxyFactory} from "src/interfaces/factories/ITransferProxy.sol";

contract TransferProxy is ITransferProxy {
    IPoolManager public immutable poolManager;
    bytes32 public immutable destination;
    address public immutable recoverer;

    constructor(address poolManager_, bytes32 destination_, address recoverer_) {
        poolManager = IPoolManager(poolManager_);
        destination = destination_;
        recoverer = recoverer_;
    }

    /// @inheritdoc ITransferProxy
    function transfer(address asset, uint128 amount) external {
        poolManager.transfer(asset, destination, amount);
    }

    /// @inheritdoc ITransferProxy
    function recover(address asset, uint128 amount) external {
        require(msg.sender == recoverer, "TransferProxy/not-recoverer");
        SafeTransferLib.safeTransfer(asset, address(recoverer), amount);
    }
}

interface TransferProxyFactoryLike {
    function newTransferProxy(address poolManager, bytes32 destination) external returns (address);
}

/// @title  Restricted Transfer Proxy Factory
/// @dev    Utility for deploying contracts that have a fixed destination for transfers
///         Users can send tokens to the TransferProxy, from a service that only supports
///         ERC20 transfers and not full contract calls.
///         If tokens are incorrectly sent, they can be recovered to the recoverer address.
contract TransferProxyFactory is ITransferProxyFactory {
    address public immutable poolManager;

    /// @inheritdoc ITransferProxyFactory
    mapping(bytes32 id => address proxy) public proxies;

    constructor(address poolManager_) {
        poolManager = poolManager_;
    }

    /// @inheritdoc ITransferProxyFactory
    function newTransferProxy(bytes32 destination, address recoverer) public returns (address) {
        bytes32 id = keccak256(bytes.concat(destination, bytes20(recoverer)));
        require(proxies[id] == address(0), "TransferProxyFactory/proxy-already-deployed");

        address proxy = address(new TransferProxy(poolManager, destination, recoverer));
        proxies[id] = proxy;
        return proxy;
    }
}
