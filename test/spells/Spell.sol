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
    function getLiquidityPool(uint64 poolId, bytes16 trancheId, address currency) external returns (address);
}

interface LiquidityPoolLike {
    function poolId() external returns (uint64);
    function trancheId() external returns (bytes16);
    function asset() external returns (address);
}

// Spell to mirate the LiquidityPool factory contract
contract Spell is Addresses {
    bool public done;
    string public constant description = "Liquidity Pool Factory migration spell";

    address public constant LIQUIDITY_POOL_FACTORY_NEW = address(0x8273E36EEcf7A8604BEdEe68FC24Af121B64f165);
    address public constant DEPRECATED_LIQUIDITY_POOL = address(0xa0872E8D2975483b2Ab4Afcee729133D8666F6f5);

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
        migrateLiquidtyPoolFactory();
        removeLiquidityPool();

        // revoke all permissions from spell
        AuthLike(address(root)).deny(self);
        AuthLike(LIQUIDITY_POOL_FACTORY_NEW).deny(self);
        AuthLike(poolManager).deny(self);
    }

    function migrateLiquidtyPoolFactory() internal {
        AuthLike(LIQUIDITY_POOL_FACTORY_NEW).rely(poolManager);
        AuthLike(LIQUIDITY_POOL_FACTORY_NEW).deny(deployer);
        FileLike(poolManager).file("liquidityPoolFactory", LIQUIDITY_POOL_FACTORY_NEW);
    }

    function removeLiquidityPool() internal {
        LiquidityPoolLike lp = LiquidityPoolLike(DEPRECATED_LIQUIDITY_POOL);
        address liquidityPoolToRemove =
            PoolManagerLike(poolManager).getLiquidityPool(lp.poolId(), lp.trancheId(), lp.asset());
        require(liquidityPoolToRemove == DEPRECATED_LIQUIDITY_POOL, "SPELL - unknown Liquidity Pool");
        PoolManagerLike(poolManager).removeLiquidityPool(lp.poolId(), lp.trancheId(), lp.asset());
    }
}
