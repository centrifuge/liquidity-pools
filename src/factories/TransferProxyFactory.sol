// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

interface PoolManagerLike {
    function transfer(address currency, bytes32 recipient, uint128 amount) external;
}

interface ERC20Like {
    function approve(address spender, uint256 value) external;
}

contract TransferProxy {
    PoolManagerLike public immutable poolManager;
    bytes32 public immutable destination;

    constructor(address poolManager_, bytes32 destination_) {
        poolManager = PoolManagerLike(poolManager_);
        destination = destination_;
    }

    function transfer(address currency, uint128 amount) external {
        ERC20Like(currency).approve(address(poolManager), amount);
        poolManager.transfer(currency, destination, amount);
    }
}

interface TransferProxyFactoryLike {
    function newTransferProxy(address poolManager, bytes32 destination) external returns (address);
}

/// @title  Restricted Transfer Proxy Factory
/// @dev    Utility for deploying contracts that have a fixed destination for transfers
contract TransferProxyFactory {
    address public immutable poolManager;

    mapping(bytes32 destination => address proxy) public proxies;

    constructor(address poolManager_) {
        poolManager = poolManager_;
    }

    function newTransferProxy(bytes32 destination) public returns (address) {
        require(proxies[destination] == address(0), "TransferProxyFactory/proxy-already-deployed");
        address proxy = address(new TransferProxy(poolManager, destination));
        proxies[destination] = proxy;
        return proxy;
    }
}
