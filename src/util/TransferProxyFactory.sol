// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

interface PoolManagerLike {
    function transfer(address currency, bytes32 recipient, uint128 amount) external;
}

interface ERC20Like {
    function approve(address token, address spender, uint256 value) external;
}

contract RestrictedTransferProxy {

    PoolManagerLike immutable poolManager;

    constructor(address poolManager_, bytes32 destination) {
        poolManager = PoolManagerLike(poolManager_);
    }

    function transfer(address currency, uint128 amount) external {
        ERC20Like(currency).approve(address(poolManager), currency, amount);
        poolManager.transfer(currency, amount);
    }

}

interface RestrictedTransferProxyFactoryLike {
    function newRestrictedTransferProxy(bytes32 destination)
        external
        returns (address);
}

/// @title  Restricted Transfer Proxy Factory
/// @dev    Utility for deploying contracts that have a fixed destination for transfers
contract RestrictedTransferProxyFactory {
    address immutable poolManager;

    constructor(address poolManager_) {
        poolManager = poolManager_;
    }

    function newRestrictedTransferProxy(bytes32 destination)
        public
        returns (address)
    {
        RestrictedTransferProxy restrictedTransferProxy = new RestrictedTransferProxy(destination);
        return (address(restrictedTransferProxy));
    }
}
