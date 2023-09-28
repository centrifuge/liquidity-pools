// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import {Root} from "src/Root.sol";
import {AxelarRouter} from "src/gateway/routers/axelar/Router.sol";
import {Gateway, InvestmentManagerLike} from "src/gateway/Gateway.sol";
import {InvestmentManager} from "src/InvestmentManager.sol";
import {PoolManager} from "src/PoolManager.sol";
import {Escrow} from "src/Escrow.sol";
import {UserEscrow} from "src/UserEscrow.sol";
import {PauseAdmin} from "src/admins/PauseAdmin.sol";
import {DelayedAdmin} from "src/admins/DelayedAdmin.sol";
import {LiquidityPoolFactory, RestrictionManagerFactory, TrancheTokenFactory} from "src/util/Factory.sol";
import "forge-std/Script.sol";

interface RouterLike {
    function file(bytes32 what, address data) external;
    function rely(address who) external;
    function deny(address who) external;
}

contract Deployer is Script {
    uint256 internal constant delay = 48 hours;

    address admin;

    Root public root;
    InvestmentManager public investmentManager;
    PoolManager public poolManager;
    Escrow public escrow;
    UserEscrow public userEscrow;
    PauseAdmin public pauseAdmin;
    DelayedAdmin public delayedAdmin;
    Gateway public gateway;
    address public liquidityPoolFactory;
    address public restrictionManagerFactory;
    address public trancheTokenFactory;

    function deployInvestmentManager() public {
        escrow = new Escrow();
        userEscrow = new UserEscrow();
        root = new Root(address(escrow), delay);

        investmentManager = new InvestmentManager(address(escrow), address(userEscrow));

        liquidityPoolFactory = address(new LiquidityPoolFactory(address(root)));
        restrictionManagerFactory = address(new RestrictionManagerFactory(address(root)));
        trancheTokenFactory = address(new TrancheTokenFactory(address(root)));
        investmentManager = new InvestmentManager(address(escrow), address(userEscrow));
        poolManager =
            new PoolManager(address(escrow), liquidityPoolFactory, restrictionManagerFactory, trancheTokenFactory);

        LiquidityPoolFactory(liquidityPoolFactory).rely(address(poolManager));
        TrancheTokenFactory(trancheTokenFactory).rely(address(poolManager));
        RestrictionManagerFactory(restrictionManagerFactory).rely(address(poolManager));

        LiquidityPoolFactory(liquidityPoolFactory).rely(address(root));
        TrancheTokenFactory(trancheTokenFactory).rely(address(root));
        RestrictionManagerFactory(restrictionManagerFactory).rely(address(root));
    }

    function wire(address router) public {
        // Deploy gateway and admins
        pauseAdmin = new PauseAdmin(address(root));
        delayedAdmin = new DelayedAdmin(address(root), address(pauseAdmin));
        gateway = new Gateway(address(root), address(investmentManager), address(poolManager), address(router));
        pauseAdmin.rely(address(delayedAdmin));
        root.rely(address(pauseAdmin));
        root.rely(address(delayedAdmin));
        root.rely(address(gateway));

        // Wire gateway
        investmentManager.file("poolManager", address(poolManager));
        poolManager.file("investmentManager", address(investmentManager));
        investmentManager.file("gateway", address(gateway));
        poolManager.file("gateway", address(gateway));
        investmentManager.rely(address(root));
        investmentManager.rely(address(poolManager));
        poolManager.rely(address(root));
        gateway.rely(address(root));
        RouterLike(router).rely(address(root));
        Escrow(address(escrow)).rely(address(root));
        Escrow(address(escrow)).rely(address(investmentManager));
        UserEscrow(address(userEscrow)).rely(address(root));
        UserEscrow(address(userEscrow)).rely(address(investmentManager));
        Escrow(address(escrow)).rely(address(poolManager));
    }

    function giveAdminAccess() public {
        pauseAdmin.rely(address(admin));
        delayedAdmin.rely(address(admin));
    }

    function removeDeployerAccess(address router) public {
        RouterLike(router).deny(address(this));
        root.deny(address(this));
        investmentManager.deny(address(this));
        poolManager.deny(address(this));
        escrow.deny(address(this));
        gateway.deny(address(this));
        pauseAdmin.deny(address(this));
        delayedAdmin.deny(address(this));
    }
}
