// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import "deployments/ETH_MAINNET.sol";

interface RootLike {
    function relyContract(address, address) external;
}

interface FileLike {
    function file(bytes32, address) external;
}

interface AuthLike {
    function rely(address) external;
    function deny(address) external;
}

interface PoolManagerLike {
    function removeLiquidityPool(uint64 poolId, bytes16 trancheId, address currency) external;
    function deployLiquidityPool(uint64 poolId, bytes16 trancheId, address currency) external returns (address);
    function getLiquidityPool(uint64 poolId, bytes16 trancheId, address currency) external returns (address);
}

interface LiquidityPoolLike {
    function poolId() external returns (uint64);
    function trancheId() external returns (bytes16);
    function asset() external returns (address);
}

// Spell to migrate the LiquidityPool factory contract
contract Spell is Addresses {
    bool public done;
    string public constant description = "Liquidity Pool Factory migration spell";

    address public constant LIQUIDITY_POOL_FACTORY_NEW = address(0x7f93eDB11d5Dc23F04C4E9382aa0d3F31E95BF2C);
    address public constant DEPRECATED_LIQUIDITY_POOL = address(0xa0872E8D2975483b2Ab4Afcee729133D8666F6f5);
    address public newLiquidityPool;

    address self;

    function cast() public {
        require(!done, "spell-already-cast");
        done = true;
        execute();
    }

    function execute() internal {
        self = address(this);

        // give spell required permissions
        RootLike root = RootLike(root);
        root.relyContract(LIQUIDITY_POOL_FACTORY_NEW, self);
        root.relyContract(poolManager, self);

        // spell magic
        migrateLiquidityPoolFactory();
        migrateLiquidityPool();

        // revoke all permissions from spell
        AuthLike(address(root)).deny(self);
        AuthLike(LIQUIDITY_POOL_FACTORY_NEW).deny(self);
        AuthLike(poolManager).deny(self);
    }

    function migrateLiquidityPoolFactory() internal {
        AuthLike(LIQUIDITY_POOL_FACTORY_NEW).rely(poolManager);
        AuthLike(LIQUIDITY_POOL_FACTORY_NEW).deny(deployer);
        FileLike(poolManager).file("liquidityPoolFactory", LIQUIDITY_POOL_FACTORY_NEW);
    }

    function migrateLiquidityPool() internal {
        LiquidityPoolLike deprectaedLP = LiquidityPoolLike(DEPRECATED_LIQUIDITY_POOL);
        address deprectaedLP_ = PoolManagerLike(poolManager).getLiquidityPool(
            deprectaedLP.poolId(), deprectaedLP.trancheId(), deprectaedLP.asset()
        );
        require(deprectaedLP_ == DEPRECATED_LIQUIDITY_POOL, "SPELL - unknown Liquidity Pool");
        // remove deprectaed pool
        PoolManagerLike(poolManager).removeLiquidityPool(
            deprectaedLP.poolId(), deprectaedLP.trancheId(), deprectaedLP.asset()
        );
        // add new pool
        newLiquidityPool = PoolManagerLike(poolManager).deployLiquidityPool(
            deprectaedLP.poolId(), deprectaedLP.trancheId(), deprectaedLP.asset()
        );
    }
}
