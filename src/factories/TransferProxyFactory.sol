// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import {SafeTransferLib} from "src/libraries/SafeTransferLib.sol";

interface PoolManagerLike {
    function transfer(address currency, bytes32 recipient, uint128 amount) external;
}

contract TransferProxy {
    PoolManagerLike public immutable poolManager;
    bytes32 public immutable destination;
    address public immutable recoverer;

    constructor(address poolManager_, bytes32 destination_, address recoverer_) {
        poolManager = PoolManagerLike(poolManager_);
        destination = destination_;
        recoverer = recoverer_;
    }

    // Anyone can transfer tokens.
    function transfer(address currency, uint128 amount) external {
        SafeTransferLib.safeApprove(currency, address(poolManager), amount);
        poolManager.transfer(currency, destination, amount);
    }

    // The recoverer can receive tokens back. This is not permissionless as this could lead
    // to griefing issues, where tokens are recovered before being transferred out.
    function recover(address currency, uint128 amount) external {
        require(msg.sender == recoverer, "TransferProxy/not-recoverer");
        SafeTransferLib.safeTransfer(currency, address(recoverer), amount);
    }
}

interface TransferProxyFactoryLike {
    function newTransferProxy(address poolManager, bytes32 destination) external returns (address);
}

/// @title  Restricted Transfer Proxy Factory
/// @dev    Utility for deploying contracts that have a fixed destination for transfers
///         Users can send tokens to the TransferProxy, from a service that only supports
///         ERC20 transfers and not full contract calls (such as Circle).
///         If tokens are incorrectly sent, they can be recovered to the recoverer address.
contract TransferProxyFactory {
    address public immutable poolManager;

    // id = keccak256(destination + recoverer)
    mapping(bytes32 id => address proxy) public proxies;

    constructor(address poolManager_) {
        poolManager = poolManager_;
    }

    function newTransferProxy(bytes32 destination, address recoverer) public returns (address) {
        bytes32 id = keccak256(bytes.concat(destination, bytes20(recoverer)));
        require(proxies[id] == address(0), "TransferProxyFactory/proxy-already-deployed");

        address proxy = address(new TransferProxy(poolManager, destination, recoverer));
        proxies[id] = proxy;
        return proxy;
    }
}
