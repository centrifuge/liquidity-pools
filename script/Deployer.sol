// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.18;

import {Root} from "src/Root.sol";
import {AxelarEVMRouter} from "src/gateway/routers/axelar/EVMRouter.sol";
import {Gateway, InvestmentManagerLike} from "src/gateway/Gateway.sol";
import {InvestmentManager} from "src/InvestmentManager.sol";
import {TokenManager} from "src/TokenManager.sol";
import {Escrow} from "src/Escrow.sol";
import {PauseAdmin} from "src/admins/PauseAdmin.sol";
import {DelayedAdmin} from "src/admins/DelayedAdmin.sol";
import {LiquidityPoolFactory, TrancheTokenFactory} from "src/util/Factory.sol";
import "forge-std/Script.sol";

interface RouterLike {
    function file(bytes32 what, address data) external;
    function rely(address who) external;
    function deny(address who) external;
}

contract Deployer is Script {
    uint256 delay = 48 hours;

    address admin;

    Root root;
    InvestmentManager investmentManager;
    TokenManager tokenManager;
    Escrow escrow;
    PauseAdmin pauseAdmin;
    DelayedAdmin delayedAdmin;
    Gateway gateway;

    function deployInvestmentManager() public {
        escrow = new Escrow();
        root = new Root(address(escrow), delay);
        address liquidityPoolFactory = address(new LiquidityPoolFactory(address(root)));
        address trancheTokenFactory = address(new TrancheTokenFactory(address(root)));
        investmentManager = new InvestmentManager(address(escrow), liquidityPoolFactory, trancheTokenFactory);
    }

    function wire(address router) public {
        // Deploy token manager
        tokenManager = new TokenManager(address(escrow));

        // Deploy gateway and admins
        pauseAdmin = new PauseAdmin(address(root));
        delayedAdmin = new DelayedAdmin(address(root));
        pauseAdmin.rely(address(delayedAdmin));
        root.rely(address(pauseAdmin));
        root.rely(address(delayedAdmin));
        gateway = new Gateway(address(root), address(investmentManager), address(tokenManager), address(router));

        // Wire gateway
        investmentManager.file("tokenManager", address(tokenManager));
        tokenManager.file("investmentManager", address(investmentManager));
        investmentManager.file("gateway", address(gateway));
        tokenManager.file("gateway", address(gateway));
        gateway.rely(address(pauseAdmin));
        gateway.rely(address(delayedAdmin));
        investmentManager.rely(address(gateway));
        tokenManager.rely(address(gateway));
        RouterLike(router).rely(address(gateway));
        Escrow(address(escrow)).rely(address(gateway));
        Escrow(address(escrow)).rely(address(investmentManager));
        Escrow(address(escrow)).rely(address(tokenManager));
    }

    function giveAdminAccess() public {
        pauseAdmin.rely(address(admin));
        delayedAdmin.rely(address(admin));
    }

    function removeDeployerAccess(address router) public {
        RouterLike(router).deny(address(this));
        investmentManager.deny(address(this));
        tokenManager.deny(address(this));
        escrow.deny(address(this));
        gateway.deny(address(this));
        pauseAdmin.deny(address(this));
        delayedAdmin.deny(address(this));
    }
}
