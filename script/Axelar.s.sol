// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import {AxelarRouter} from "src/gateway/routers/axelar/Router.sol";
import {ERC20} from "src/token/ERC20.sol";
import {Deployer, RouterLike} from "./Deployer.sol";

interface LiquidityPoolLike {
    function requestDeposit(uint256 assets, address owner) external;
}

// Script to deploy Liquidity Pools with an Axelar router.
contract AxelarScript is Deployer {
    function setUp() public {}

    function run() public {
        vm.startBroadcast();

        admin = vm.envAddress("ADMIN");

        deployInvestmentManager();
        AxelarRouter router = new AxelarRouter(
                address(vm.envAddress("AXELAR_GATEWAY"))
        );
        wire(address(router));
        router.file("gateway", address(gateway));

        // Set up test data
        if (vm.envBool("SETUP_TEST_DATA")) {
            ERC20 currency = new ERC20(18);
            currency.mint(msg.sender, 1000 * 10 ** 18);

            root.relyContract(address(poolManager), msg.sender);
            poolManager.file("gateway", msg.sender);
            root.relyContract(address(investmentManager), msg.sender);
            investmentManager.file("gateway", msg.sender);

            poolManager.addCurrency(1, address(currency));
            poolManager.addPool(1171854325);
            poolManager.addTranche(1171854325, 0x102f4ef817340a8839a515d2c73a7c1d, "Some Token", "ST", 6);
            poolManager.deployTranche(1171854325, 0x102f4ef817340a8839a515d2c73a7c1d);
            poolManager.allowPoolCurrency(1171854325, 1);
            poolManager.deployLiquidityPool(1171854325, 0x102f4ef817340a8839a515d2c73a7c1d, address(currency));
            poolManager.updateMember(1171854325, 0x102f4ef817340a8839a515d2c73a7c1d, msg.sender, type(uint64).max);

            poolManager.file("gateway", address(gateway));
            investmentManager.file("gateway", address(gateway));

            LiquidityPoolLike liquidityPool = LiquidityPoolLike(
                poolManager.getLiquidityPool(1171854325, 0x102f4ef817340a8839a515d2c73a7c1d, address(currency))
            );
            currency.approve(address(investmentManager), 1000 * 10 ** 18);
            liquidityPool.requestDeposit(200 * 10 ** 18, msg.sender);
            liquidityPool.requestDeposit(200 * 10 ** 18, msg.sender);
            liquidityPool.requestDeposit(200 * 10 ** 18, msg.sender);
            liquidityPool.requestDeposit(200 * 10 ** 18, msg.sender);
            liquidityPool.requestDeposit(200 * 10 ** 18, msg.sender);
        }

        giveAdminAccess();
        removeDeployerAccess(address(router));

        vm.stopBroadcast();
    }
}
