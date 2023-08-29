// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.18;
pragma abicoder v2;

import {InvestmentManager, Pool, Tranche} from "src/InvestmentManager.sol";
import {Gateway, RouterLike} from "src/gateway/Gateway.sol";
import {MockHomeLiquidityPools} from "test/mock/MockHomeLiquidityPools.sol";
import {Escrow} from "src/Escrow.sol";
import {PauseAdmin} from "src/admins/PauseAdmin.sol";
import {DelayedAdmin} from "src/admins/DelayedAdmin.sol";
import {MockXcmRouter} from "test/mock/MockXcmRouter.sol";
import {TokenManager} from "src/TokenManager.sol";
import {ERC20} from "src/token/ERC20.sol";
import {TrancheToken} from "src/token/Tranche.sol";
import {LiquidityPoolTest} from "test/LiquidityPool.t.sol";
import {PermissionlessRouter} from "test/mock/PermissionlessRouter.sol";
import {Root} from "src/Root.sol";

import {AxelarEVMScript} from "script/AxelarEVM.s.sol";
import {PermissionlessScript} from "script/Permissionless.s.sol";
import "forge-std/Test.sol";

interface ApproveLike {
    function approve(address, uint256) external;
}

contract DeployTest is Test {
    InvestmentManager investmentManager;
    Gateway gateway;
    Root root;
    MockHomeLiquidityPools mockLiquidityPools;
    RouterLike router;
    Escrow escrow;
    PauseAdmin pauseAdmin;
    DelayedAdmin delayedAdmin;
    TokenManager tokenManager;

    address DAI;
    address user;

    function setUp() public {
        // Run the AxelarEVM deploy script
        PermissionlessScript script = new PermissionlessScript();
        script.run();

        DAI = address(0x6B175474E89094C44Da98b954EedeAC495271d0F);
        user = address(0xFED);

        investmentManager = script.investmentManager();
        gateway = script.gateway();
        root = script.root();
        escrow = script.escrow();
        pauseAdmin = script.pauseAdmin();
        delayedAdmin = script.delayedAdmin();
        tokenManager = script.tokenManager();

        RouterLike router = RouterLike(gateway.outgoingRouter());
        mockLiquidityPools = new MockHomeLiquidityPools(address(router));
    }

    function deployPoolAndTranche(
        uint64 poolId,
        bytes16 trancheId,
        string memory tokenName,
        string memory tokenSymbol,
        uint8 decimals,
        uint128 price
    ) public {
        uint64 validUntil = uint64(block.timestamp + 1000 days);

        vm.startPrank(address(gateway));
        tokenManager.addCurrency(1, DAI);
        investmentManager.addPool(poolId);
        investmentManager.addTranche(poolId, trancheId, tokenName, tokenSymbol, decimals, price);
        investmentManager.deployTranche(poolId, trancheId);
        investmentManager.allowPoolCurrency(poolId, 1);
        investmentManager.deployLiquidityPool(poolId, trancheId, DAI);

        tokenManager.updateMember(poolId, trancheId, user, validUntil);
        vm.stopPrank();
    }

    function testDeploy(
        uint64 poolId,
        uint8 decimals,
        string memory tokenName,
        string memory tokenSymbol,
        bytes16 trancheId
    ) public {
        uint8 decimals = 6;
        uint128 price = 1e27;
        uint128 currencyId = 1;
        uint256 amount = 1000;
        uint64 validUntil = uint64(block.timestamp + 1000 days);
        // deployPoolAndTranche(poolId, trancheId, tokenName, tokenSymbol, decimals, price);
        LiquidityPoolTest liquidityPoolTest = new LiquidityPoolTest();
        liquidityPoolTest.setUpOverride(
            root, investmentManager, tokenManager, gateway, mockLiquidityPools, router, escrow, ERC20(DAI), address(this)
        );
        liquidityPoolTest.testDepositMint(
            poolId, decimals, tokenName, tokenSymbol, trancheId, price, currencyId, amount, validUntil
        );
    }
}
